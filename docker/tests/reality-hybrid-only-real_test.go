package tls

import (
	"bufio"
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	stdtls "crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	utls "github.com/metacubex/utls"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing-vmess/vless"
	"github.com/sagernet/sing/common/logger"
	M "github.com/sagernet/sing/common/metadata"
)

var realityTestHybridOnly bool

// 只替换测试中的 ClientHello 工厂，认证、握手及证书校验仍编译实际补丁源码。
func realityTestUClient(conn net.Conn, config *utls.Config, id utls.ClientHelloID) *utls.UConn {
	spec, err := utls.UTLSIdToSpec(id)
	if err != nil {
		panic(err)
	}
	for _, extension := range spec.Extensions {
		if shares, ok := extension.(*utls.KeyShareExtension); ok {
			filtered := shares.KeyShares[:0]
			for _, share := range shares.KeyShares {
				if share.Group == utls.X25519MLKEM768 ||
					share.Group == utls.X25519 && !realityTestHybridOnly {
					filtered = append(filtered, share)
				}
			}
			shares.KeyShares = filtered
		}
	}
	connTLS := utls.UClient(conn, config, utls.HelloCustom)
	if err := connTLS.ApplyPreset(&spec); err != nil {
		panic(err)
	}
	return connTLS
}

type realityWireConn struct {
	net.Conn
	hello []byte
}

func (c *realityWireConn) Write(data []byte) (int, error) {
	if c.hello == nil && len(data) >= 5 && data[0] == 22 {
		size := int(binary.BigEndian.Uint16(data[3:5]))
		if len(data) >= 5+size {
			c.hello = bytes.Clone(data[5 : 5+size])
		}
	}
	return c.Conn.Write(data)
}

func TestRealityHybridOnlyHandshake(t *testing.T) {
	xray := "/routing-cores/xray"
	version, err := exec.Command(xray, "version").CombinedOutput()
	if err != nil || !strings.HasPrefix(string(version), "Xray 26.10.31 ") {
		t.Fatalf("unexpected Xray version: %s (%v)", version, err)
	}
	target := realityTestTarget(t)
	const publicKey = "hSDwCYkwp1R0i33ctD73Wg2_Og0mOBr066SpjqqbTmo"
	const uuid = "11111111-1111-4111-8111-111111111111"
	var requests atomic.Int64
	origin := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		fmt.Fprint(w, "padm-reality-hybrid-only-proof\n")
	}))
	defer origin.Close()
	destination := M.ParseSocksaddr(strings.TrimPrefix(origin.URL, "http://"))
	portListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := portListener.Addr().(*net.TCPAddr).Port
	portListener.Close()
	config := map[string]any{
		"log": map[string]any{"loglevel": "warning"},
		"inbounds": []any{map[string]any{
			"listen": "127.0.0.1", "port": port, "protocol": "vless",
			"settings": map[string]any{"decryption": "none", "clients": []any{map[string]any{"id": uuid}}},
			"streamSettings": map[string]any{"network": "raw", "security": "reality",
				"realitySettings": map[string]any{
					"target": target, "serverNames": []string{"www.debian.org"},
					"privateKey": "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo",
					"shortIds":   []string{"6ba85179e30d4fc2"},
				}},
		}},
		"outbounds": []any{map[string]any{"protocol": "freedom", "settings": map[string]any{
			"finalRules": []any{map[string]any{"action": "allow", "network": "tcp",
				"ip": []string{"127.0.0.1/32"}, "port": fmt.Sprint(destination.Port)}},
		}}},
	}
	root := t.TempDir()
	data, err := json.Marshal(config)
	if err != nil {
		t.Fatal(err)
	}
	configPath := filepath.Join(root, "xray.json")
	if err := os.WriteFile(configPath, data, 0600); err != nil {
		t.Fatal(err)
	}
	log, err := os.Create(filepath.Join(root, "xray.log"))
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(xray, "run", "-c", configPath)
	cmd.Stdout, cmd.Stderr = log, log
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cmd.Process.Kill()
		cmd.Wait()
		log.Close()
		if t.Failed() {
			output, _ := os.ReadFile(log.Name())
			t.Logf("Xray log:\n%s", output)
		}
	})
	address := fmt.Sprintf("127.0.0.1:%d", port)
	ready := false
	for attempt := 0; attempt < 100; attempt++ {
		conn, err := net.DialTimeout("tcp", address, 50*time.Millisecond)
		if err == nil {
			conn.Close()
			ready = true
			break
		}
		time.Sleep(20 * time.Millisecond)
	}
	if !ready {
		t.Fatal("Xray did not listen")
	}
	for _, hybridOnly := range []bool{false, true} {
		name := "dual"
		if hybridOnly {
			name = "hybrid-only"
		}
		t.Run(name, func(t *testing.T) {
			realityTestHybridOnly = hybridOnly
			request := func(t *testing.T, public, shortID, user string) error {
				t.Helper()
				cfg, err := NewRealityClient(context.Background(), logger.NOP(), "www.debian.org",
					option.OutboundTLSOptions{
						Enabled: true, ServerName: "www.debian.org", ALPN: []string{"http/1.1"},
						UTLS:    &option.OutboundUTLSOptions{Enabled: true, Fingerprint: "chrome"},
						Reality: &option.OutboundRealityOptions{Enabled: true, PublicKey: public, ShortID: shortID},
					})
				if err != nil {
					t.Fatal(err)
				}
				raw, err := net.DialTimeout("tcp", address, time.Second)
				if err != nil {
					t.Fatal(err)
				}
				defer raw.Close()
				// REALITY 启动探测缓存未就绪时按 5 秒轮询，限时需覆盖该等待。
				raw.SetDeadline(time.Now().Add(10 * time.Second))
				wire := &realityWireConn{Conn: raw}
				secured, err := cfg.(*RealityClientConfig).ClientHandshake(context.Background(), wire)
				if wire.hello != nil {
					hello := utls.UnmarshalClientHello(wire.hello)
					if hello == nil {
						t.Fatal("cannot decode transmitted ClientHello")
					}
					expected := 2
					if hybridOnly {
						expected = 1
					}
					if len(hello.KeyShares) != expected || hello.KeyShares[0].Group != utls.X25519MLKEM768 ||
						len(hello.KeyShares[0].Data) != 1216 {
						t.Fatal("transmitted ClientHello does not match the fixed key shares")
					}
					if !hybridOnly && (hello.KeyShares[1].Group != utls.X25519 || len(hello.KeyShares[1].Data) != 32) {
						t.Fatal("missing standalone X25519 share")
					}
				}
				if err != nil {
					return err
				}
				defer secured.Close()
				if wire.hello == nil || !secured.ConnectionState().HandshakeComplete ||
					secured.ConnectionState().Version != stdtls.VersionTLS13 {
					t.Fatal("missing verified TLS 1.3 handshake")
				}
				client, err := vless.NewClient(user, "", logger.NOP())
				if err != nil {
					t.Fatal(err)
				}
				proxy, err := client.DialConn(secured, destination)
				if err != nil {
					return err
				}
				defer proxy.Close()
				if _, err := fmt.Fprint(proxy, "GET /proof HTTP/1.1\r\nHost: origin.padm.test\r\nConnection: close\r\n\r\n"); err != nil {
					return err
				}
				response, err := http.ReadResponse(bufio.NewReader(proxy), nil)
				if err != nil {
					return err
				}
				defer response.Body.Close()
				body, err := io.ReadAll(io.LimitReader(response.Body, 1024))
				if err != nil {
					return err
				}
				if response.StatusCode != 200 || string(body) != "padm-reality-hybrid-only-proof\n" {
					return fmt.Errorf("unexpected origin response")
				}
				return nil
			}
			positive := func(t *testing.T) {
				t.Helper()
				before := requests.Load()
				if err := request(t, publicKey, "6ba85179e30d4fc2", uuid); err != nil {
					t.Fatal(err)
				}
				if requests.Load() != before+1 {
					t.Fatal("positive request did not reach origin exactly once")
				}
			}
			if hybridOnly && os.Getenv("PADM_REALITY_BASELINE") == "1" {
				if err := request(t, publicKey, "6ba85179e30d4fc2", uuid); err == nil || !strings.Contains(err.Error(), "nil ecdheKey") {
					t.Fatalf("published .1 did not reproduce nil ecdheKey: %v", err)
				}
				t.Log("published .1 rejects fixed hybrid-only before sending ClientHello")
				return
			}
			positive(t)
			wrongPublic, _ := base64.RawURLEncoding.DecodeString(publicKey)
			wrongPublic[0] ^= 1
			for _, invalid := range []struct{ name, public, shortID, user string }{
				{"public-key", base64.RawURLEncoding.EncodeToString(wrongPublic), "6ba85179e30d4fc2", uuid},
				{"short-id", publicKey, "7ba85179e30d4fc2", uuid},
				{"uuid", publicKey, "6ba85179e30d4fc2", "22222222-2222-4222-8222-222222222222"},
			} {
				t.Run("reject-"+invalid.name, func(t *testing.T) {
					before := requests.Load()
					if err := request(t, invalid.public, invalid.shortID, invalid.user); err == nil {
						t.Fatal("invalid client obtained complete business response")
					}
					if requests.Load() != before {
						t.Fatal("invalid client reached origin")
					}
					positive(t)
				})
			}
			t.Log("fixed wire key shares, verified Reality, full VLESS body and authentication refusals passed")
		})
	}
}

func realityTestTarget(t *testing.T) string {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	cert := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "www.debian.org"},
		DNSNames: []string{"www.debian.org"}, NotBefore: time.Now().Add(-time.Hour),
		NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	for n := 0; n < 180; n++ {
		cert.DNSNames = append(cert.DNSNames, fmt.Sprintf("padding-%03d.padm.test", n))
	}
	der, err := x509.CreateCertificate(rand.Reader, cert, cert, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	if len(der) <= 3500 {
		t.Fatal("target certificate is too short")
	}
	listener, err := stdtls.Listen("tcp", "127.0.0.1:0", &stdtls.Config{
		Certificates: []stdtls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}, MinVersion: stdtls.VersionTLS13,
		MaxVersion: stdtls.VersionTLS13, NextProtos: []string{"h2", "http/1.1"},
		CurvePreferences: []stdtls.CurveID{stdtls.X25519MLKEM768},
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				conn.SetDeadline(time.Now().Add(10 * time.Second))
				io.Copy(io.Discard, conn)
			}()
		}
	}()
	return listener.Addr().String()
}
