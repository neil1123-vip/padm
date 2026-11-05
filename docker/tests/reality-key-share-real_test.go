package reality

import (
	"bytes"
	"crypto/ecdh"
	"crypto/rand"
	"net"
	"testing"

	utls "github.com/metacubex/utls"
)

func TestRealityKeySharePrivateKeys(t *testing.T) {
	server, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name          string
		plain, hybrid bool
	}{
		{"dual", true, true},
		{"hybrid-only", false, true},
		{"x25519-only", true, false},
		{"empty", false, false},
	} {
		t.Run(test.name, func(t *testing.T) {
			spec, err := utls.UTLSIdToSpec(utls.HelloChrome_Auto)
			if err != nil {
				t.Fatal(err)
			}
			for _, extension := range spec.Extensions {
				if shares, ok := extension.(*utls.KeyShareExtension); ok {
					filtered := shares.KeyShares[:0]
					for _, share := range shares.KeyShares {
						if share.Group == utls.X25519MLKEM768 && test.hybrid ||
							share.Group == utls.X25519 && test.plain {
							filtered = append(filtered, share)
						}
					}
					shares.KeyShares = filtered
				}
			}
			client, peer := net.Pipe()
			defer client.Close()
			defer peer.Close()
			conn := utls.UClient(client, &utls.Config{
				ServerName: "reality.padm.test", NextProtos: []string{"h2"},
			}, utls.HelloCustom)
			if err := conn.ApplyPreset(&spec); err != nil {
				t.Fatal(err)
			}
			if err := conn.BuildHandshakeState(); err != nil {
				t.Fatal(err)
			}
			keys := conn.HandshakeState.State13.KeyShareKeys
			if keys == nil {
				t.Fatal("missing generated private keys")
			}
			var plain, hybrid []byte
			for _, share := range conn.HandshakeState.Hello.KeyShares {
				switch share.Group {
				case utls.X25519:
					if len(share.Data) != 32 {
						t.Fatalf("invalid X25519 share length: %d", len(share.Data))
					}
					plain = share.Data
				case utls.X25519MLKEM768:
					if len(share.Data) != 1184+32 {
						t.Fatalf("invalid hybrid share length: %d", len(share.Data))
					}
					hybrid = share.Data[1184:]
				}
			}
			if (len(plain) > 0) != test.plain || (len(hybrid) > 0) != test.hybrid {
				t.Fatal("ClientHello does not contain the requested shares")
			}
			if !test.plain && !test.hybrid {
				if _, err := realityAuthPrivateKey(conn); err == nil {
					t.Fatal("ClientHello without a key share was accepted")
				}
				return
			}
			check := func(key *ecdh.PrivateKey, wire []byte) {
				t.Helper()
				if key == nil || !bytes.Equal(key.PublicKey().Bytes(), wire) {
					t.Fatal("private key does not match the ClientHello share")
				}
				public, err := ecdh.X25519().NewPublicKey(wire)
				if err != nil {
					t.Fatal(err)
				}
				expected, err := server.ECDH(public)
				if err != nil {
					t.Fatal(err)
				}
				actual, err := key.ECDH(server.PublicKey())
				if err != nil || !bytes.Equal(actual, expected) {
					t.Fatal("Reality authentication secrets differ")
				}
			}
			if plain != nil {
				check(keys.Ecdhe, plain)
			}
			if hybrid != nil {
				check(keys.MlkemEcdhe, hybrid)
			}
			selected, err := realityAuthPrivateKey(conn)
			if err != nil {
				t.Fatal(err)
			}
			if keys.Ecdhe != selected {
				t.Fatal("TLS handshake and Reality authentication do not share the selected private key")
			}
			wire := plain
			if wire == nil {
				wire = hybrid
			}
			check(selected, wire)
			t.Logf("wire-x25519=%t wire-hybrid=%t Ecdhe-nil=%t MlkemEcdhe-nil=%t",
				plain != nil, hybrid != nil, keys.Ecdhe == nil, keys.MlkemEcdhe == nil)
		})
	}
}
