#!/usr/bin/env bash

singBoxGrpcResponseToStatsJson() (
    set -o pipefail
    local responseFile=$1
    od -An -v -tu1 "${responseFile}" | awk '
      { for (i = 1; i <= NF; i++) bytes[++count] = $i }
      function readVarint(limit,    byte, shift, value) {
        shift = 0
        value = 0
        while (position <= limit && shift <= 63) {
          byte = bytes[position++]
          value += (byte % 128) * (2 ^ shift)
          if (byte < 128) { varintValue = value; return 1 }
          shift += 7
        }
        return 0
      }
      function skipField(wire, limit,    fieldLength) {
        if (wire == 0) return readVarint(limit)
        if (wire == 1) { position += 8; return position <= limit + 1 }
        if (wire == 2) {
          if (!readVarint(limit)) return 0
          fieldLength = varintValue
          position += fieldLength
          return position <= limit + 1
        }
        if (wire == 5) { position += 4; return position <= limit + 1 }
        return 0
      }
      function readStat(limit,    key, field, wire, fieldLength, fieldEnd, i, statName, statValue) {
        statName = ""
        statValue = 0
        while (position <= limit) {
          if (!readVarint(limit)) return 0
          key = varintValue
          field = int(key / 8)
          wire = key % 8
          if (field == 1 && wire == 2) {
            if (!readVarint(limit)) return 0
            fieldLength = varintValue
            fieldEnd = position + fieldLength - 1
            if (fieldEnd > limit) return 0
            for (i = position; i <= fieldEnd; i++) statName = statName sprintf("%c", bytes[i])
            position = fieldEnd + 1
          } else if (field == 2 && wire == 0) {
            if (!readVarint(limit)) return 0
            statValue = varintValue
          } else if (!skipField(wire, limit)) return 0
        }
        if (position != limit + 1 || statName == "") return 0
        printf "%s\t%.0f\n", statName, statValue
        return 1
      }
      END {
        if (count < 5 || bytes[1] != 0) exit 1
        frameLength = bytes[2] * 16777216 + bytes[3] * 65536 + bytes[4] * 256 + bytes[5]
        if (frameLength != count - 5) exit 1
        position = 6
        while (position <= count) {
          if (!readVarint(count)) exit 1
          key = varintValue
          field = int(key / 8)
          wire = key % 8
          if (field == 1 && wire == 2) {
            if (!readVarint(count)) exit 1
            fieldLength = varintValue
            fieldEnd = position + fieldLength - 1
            if (fieldEnd > count || !readStat(fieldEnd)) exit 1
          } else if (!skipField(wire, count)) exit 1
        }
      }
    ' | jq -Rsc '{stat:[split("\n")[] | select(length > 0) | split("\t") as $row | {name:$row[0],value:($row[1] | tonumber)}]}'
)
