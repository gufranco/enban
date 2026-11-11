function bits_xor(a, b,   result, bit) {
  result = 0
  bit = 1
  while (a > 0 || b > 0) {
    if (a % 2 != b % 2) result += bit
    a = int(a / 2)
    b = int(b / 2)
    bit *= 2
  }
  return result
}

function crc_table(   i, crc, k) {
  for (i = 0; i < 256; i++) {
    crc = i * 256
    for (k = 0; k < 8; k++) crc = (crc >= 32768 ? bits_xor(crc * 2 - 65536, 4129) : crc * 2)
    CRC[i] = crc
  }
}

function clear(n,   i) {
  for (i = 0; i < n; i++) B[i] = 0
  LEN = n
}

function u8(at, v) { B[at] = v % 256 }

function u16(at, v) {
  B[at] = v % 256
  B[at + 1] = int(v / 256) % 256
}

function u32(at, v) {
  u16(at, v % 65536)
  u16(at + 2, int(v / 65536) % 65536)
}

function u64(at, v) {
  u32(at, v % 4294967296)
  u32(at + 4, int(v / 4294967296))
}

function text(at, s,   i) {
  for (i = 1; i <= length(s); i++) B[at + i - 1] = ORD[substr(s, i, 1)]
}

function decode(s,   i, n, c, cp, need) {
  n = 0
  WIDE = 0
  for (i = 1; i <= length(s); i++) {
    c = ORD[substr(s, i, 1)]
    if (c < 128) { cp = c; need = 0 }
    else if (c >= 240) { BAD = 1; return 0 }
    else if (c >= 224) { cp = c - 224; need = 2 }
    else if (c >= 192) { cp = c - 192; need = 1 }
    else { cp = c; need = 0 }
    while (need > 0 && i < length(s)) {
      i++
      cp = cp * 64 + ORD[substr(s, i, 1)] - 128
      need--
    }
    CP[++n] = cp
    if (cp > 255) WIDE = 1
  }
  return n
}

function cs0(at, s, room,   n, i, used, step) {
  n = decode(s)
  step = WIDE ? 2 : 1
  if (n * step + 1 > room) n = int((room - 1) / step)
  B[at] = WIDE ? 16 : 8
  used = 1
  for (i = 1; i <= n; i++) {
    if (WIDE) { B[at + used] = int(CP[i] / 256); B[at + used + 1] = CP[i] % 256 }
    else B[at + used] = CP[i]
    used += step
  }
  return used
}

function dstring(at, size, s,   used) {
  used = cs0(at, s, size - 1)
  B[at + size - 1] = used
}

function regid(at, flags, ident) {
  B[at] = flags
  text(at + 1, ident)
}

function udfid(at, ident) {
  regid(at, 0, ident)
  u16(at + 24, REV)
}

function charspec(at) {
  B[at] = 0
  text(at + 1, "OSTA Compressed Unicode")
}

function stamp(at) {
  u16(at, 4096)
  u16(at + 2, substr(DATE, 1, 4) + 0)
  B[at + 4] = substr(DATE, 5, 2) + 0
  B[at + 5] = substr(DATE, 7, 2) + 0
  B[at + 6] = substr(DATE, 9, 2) + 0
  B[at + 7] = substr(DATE, 11, 2) + 0
  B[at + 8] = substr(DATE, 13, 2) + 0
}

function tag(id, where,   crc, i, sum) {
  u16(0, id)
  u16(2, TAGV)
  crc = 0
  for (i = 16; i < LEN; i++) crc = bits_xor((crc * 256) % 65536, CRC[bits_xor(int(crc / 256), B[i])])
  u16(8, crc)
  u16(10, LEN - 16)
  u32(12, where)
  sum = 0
  for (i = 0; i < 16; i++) if (i != 4) sum += B[i]
  B[4] = sum % 256
}

function emit(sector,   i, out) {
  out = ""
  for (i = 0; i < LEN; i++) out = out sprintf("\\0%03o", B[i])
  printf "W\t%d\t%s\n", sector, out
}

function longad(at, length_, block, part, uid) {
  u32(at, length_)
  u32(at + 4, block)
  u16(at + 8, part)
  u32(at + 12, uid)
}

function vrs(sector, ident) {
  clear(7)
  text(1, ident)
  B[6] = 1
  emit(sector)
}

function pvd(sector) {
  clear(512)
  u32(16, 1)
  dstring(24, 32, LABEL)
  u16(56, 1)
  u16(58, 1)
  u16(60, 2)
  u16(62, 3)
  u32(64, 1)
  u32(68, 1)
  dstring(72, 128, substr(DATE, 1, 14) "00" LABEL)
  charspec(200)
  charspec(264)
  regid(344, 0, "*enban")
  stamp(376)
  regid(388, 0, "*enban")
  tag(1, sector)
  emit(sector)
}

function iuvd(sector) {
  clear(512)
  u32(16, 2)
  udfid(20, "*UDF LV Info")
  charspec(52)
  dstring(116, 128, LABEL)
  regid(352, 0, "*enban")
  tag(4, sector)
  emit(sector)
}

function pd(sector) {
  clear(512)
  u32(16, 3)
  u16(20, 1)
  regid(24, 0, REV < 512 ? "+NSR02" : "+NSR03")
  u32(184, 1)
  u32(188, PSTART)
  u32(192, PLEN)
  regid(196, 0, "*enban")
  tag(5, sector)
  emit(sector)
}

function lvd(sector,   maps) {
  maps = META ? 70 : 6
  clear(440 + maps)
  u32(16, 4)
  charspec(20)
  dstring(84, 128, LABEL)
  u32(212, 2048)
  regid(216, 0, "*OSTA UDF Compliant")
  u16(240, REV)
  longad(248, 2048, 0, FSPART, 0)
  u32(264, maps)
  u32(268, META ? 2 : 1)
  regid(272, 0, "*enban")
  u32(432, 4096)
  u32(436, 64)
  B[440] = 1
  B[441] = 6
  u16(442, 1)
  u16(444, 0)
  if (META) {
    B[446] = 2
    B[447] = 64
    udfid(450, "*UDF Metadata Partition")
    u16(482, 1)
    u16(484, 0)
    u32(486, 0)
    u32(490, 1)
    u32(494, 4294967295)
    u32(498, 32)
    u16(502, 32)
  }
  tag(6, sector)
  emit(sector)
}

function usd(sector) {
  clear(24)
  u32(16, 5)
  tag(7, sector)
  emit(sector)
}

function td(sector, where) {
  clear(512)
  tag(8, where)
  emit(sector)
}

function sequence(first) {
  pvd(first)
  iuvd(first + 1)
  pd(first + 2)
  lvd(first + 3)
  usd(first + 4)
  td(first + 5, first + 5)
}

function anchor(sector) {
  clear(512)
  u32(16, 32768)
  u32(20, 32)
  u32(24, 32768)
  u32(28, 48)
  tag(2, sector)
  emit(sector)
}

function lvid(sector,   parts) {
  parts = META ? 2 : 1
  clear(80 + parts * 8 + 46)
  stamp(16)
  u32(28, 1)
  u64(40, NEXTUID)
  u32(72, parts)
  u32(76, 46)
  u32(80 + parts * 4, PLEN)
  if (META) u32(80 + parts * 4 + 4, MALLOC)
  regid(80 + parts * 8, 0, "*enban")
  u32(80 + parts * 8 + 32, FILES)
  u32(80 + parts * 8 + 36, DIRS)
  u16(80 + parts * 8 + 40, REV)
  u16(80 + parts * 8 + 42, REV)
  u16(80 + parts * 8 + 44, REV)
  tag(9, sector)
  emit(sector)
}

function fsd(block) {
  clear(512)
  stamp(16)
  u16(28, 3)
  u16(30, 3)
  u32(32, 1)
  u32(36, 1)
  charspec(48)
  dstring(112, 128, LABEL)
  charspec(240)
  dstring(304, 32, LABEL)
  longad(400, 2048, ICB[0], FSPART, 0)
  regid(416, 0, "*OSTA UDF Compliant")
  u16(440, REV)
  tag(256, block)
}

function entry(type, block, links, size, blocks, uid, perms, adtype, adlength,   base, ext) {
  ext = REV >= 512
  base = ext ? 216 : 176
  clear(base + adlength)
  u16(20, 4)
  u16(24, 1)
  B[27] = type
  u16(34, adtype)
  u32(36, 4294967295)
  u32(40, 4294967295)
  u32(44, perms)
  u16(48, links)
  u64(56, size)
  if (ext) {
    u64(64, size)
    u64(72, blocks)
    stamp(80)
    stamp(92)
    stamp(104)
    stamp(116)
    u32(128, 1)
    regid(168, 0, "*enban")
    u64(200, uid)
    u32(212, adlength)
  } else {
    u64(64, blocks)
    stamp(72)
    stamp(84)
    stamp(96)
    u32(108, 1)
    regid(128, 0, "*enban")
    u64(160, uid)
    u32(172, adlength)
  }
  return base
}

function put_block(block) {
  if (META) {
    emit(PSTART + 2 + block)
    emit(PSTART + 2 + MALLOC + block)
  } else emit(PSTART + block)
}

function ceil_blocks(size) { return int((size + 2047) / 2048) }

function fid_size(name) { return int((38 + (name == "" ? 0 : cs0_length(name)) + 3) / 4) * 4 }

function cs0_length(s,   n, step) {
  n = decode(s)
  step = WIDE ? 2 : 1
  if (n * step + 1 > 255) n = int(254 / step)
  return 1 + n * step
}

function base_name(path,   n) {
  n = split(path, PARTS, "/")
  return PARTS[n]
}

function parent_of(path) {
  if (index(path, "/") == 0) return ""
  sub(/\/[^\/]*$/, "", path)
  return path
}

BEGIN {
  FS = "\t"
  for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
  crc_table()
  META = REV >= 592
  TAGV = REV >= 512 ? 3 : 2
  FSPART = META ? 1 : 0
  PSTART = 272
  NODES = 1
  KIND[0] = "d"
  NAME[0] = ""
  PARENT[0] = 0
  ID[""] = 0
  BAD = 0
}

{
  path = $2
  if (path in ID) next
  n = NODES++
  ID[path] = n
  KIND[n] = $1
  NAME[n] = base_name(path)
  SIZE[n] = $3 + 0
  SOURCE[n] = $4
  up = ID[parent_of(path)]
  PARENT[n] = up
  CHILDREN[up] = CHILDREN[up] " " n
  if ($1 == "d") SUBDIRS[up]++
  decode(NAME[n])
}

END {
  if (BAD) exit 3
  next_block = 2
  for (n = 0; n < NODES; n++) {
    ICB[n] = next_block++
    if (KIND[n] != "d") continue
    total = fid_size("")
    count = split(CHILDREN[n], LIST, " ")
    for (k = 1; k <= count; k++) total += fid_size(NAME[LIST[k]])
    DIRBYTES[n] = total
    DIRBLOCK[n] = next_block
    next_block += ceil_blocks(total)
  }
  USED = next_block
  MALLOC = META ? int((USED + 31) / 32) * 32 : 0
  data = META ? 2 + 2 * MALLOC : USED
  FILES = 0
  DIRS = 0
  for (n = 0; n < NODES; n++) {
    if (KIND[n] == "d") { DIRS++; continue }
    FILES++
    if (SIZE[n] == 0) continue
    if (SIZE[n] >= 1048576) data = int((PSTART + data + 511) / 512) * 512 - PSTART
    DATA[n] = data
    data += ceil_blocks(SIZE[n])
  }
  PLEN = data
  TOTAL = PSTART + PLEN + 1
  NEXTUID = 16 + NODES
  printf "N\t%d\n", TOTAL
  vrs(16, "BEA01")
  vrs(17, REV < 512 ? "NSR02" : "NSR03")
  vrs(18, "TEA01")
  sequence(32)
  sequence(48)
  lvid(64)
  td(65, 65)
  anchor(256)
  anchor(TOTAL - 1)
  if (META) {
    base = entry(250, 0, 1, MALLOC * 2048, MALLOC, 0, 0, 0, 8)
    u32(base, MALLOC * 2048)
    u32(base + 4, 2)
    tag(266, 0)
    emit(PSTART)
    base = entry(251, 1, 1, MALLOC * 2048, MALLOC, 0, 0, 0, 8)
    u32(base, MALLOC * 2048)
    u32(base + 4, 2 + MALLOC)
    tag(266, 1)
    emit(PSTART + 1)
  }
  fsd(0)
  put_block(0)
  clear(512)
  tag(8, 1)
  put_block(1)
  for (n = 0; n < NODES; n++) {
    uid = n == 0 ? 0 : 15 + n
    if (KIND[n] == "d") directory(n, uid)
    else file(n, uid)
  }
}

function directory(n, uid,   base, count, k, child, at, blocks, i) {
  blocks = ceil_blocks(DIRBYTES[n])
  base = entry(4, ICB[n], 1 + SUBDIRS[n], DIRBYTES[n], blocks, uid, 5285, 1, 16)
  longad(base, DIRBYTES[n], DIRBLOCK[n], FSPART, 0)
  tag(REV >= 512 ? 266 : 261, ICB[n])
  put_block(ICB[n])
  delete STREAM
  at = 0
  at = fid(at, n, PARENT[n], "", 10)
  count = split(CHILDREN[n], LIST, " ")
  for (k = 1; k <= count; k++) {
    child = LIST[k]
    at = fid(at, n, child, NAME[child], KIND[child] == "d" ? 2 : 0)
  }
  for (k = 0; k < blocks; k++) {
    clear(2048)
    for (i = 0; i < 2048; i++) if ((k * 2048 + i) in STREAM) B[i] = STREAM[k * 2048 + i]
    LEN = (k == blocks - 1) ? DIRBYTES[n] - k * 2048 : 2048
    put_block(DIRBLOCK[n] + k)
  }
}

function fid(at, dir, target, name, flags,   size, i, used, start) {
  size = fid_size(name)
  clear(size)
  u16(16, 1)
  B[18] = flags
  used = name == "" ? 0 : cs0(38, name, 255)
  B[19] = used
  longad(20, 2048, ICB[target], FSPART, target == 0 ? 0 : 15 + target)
  tag(257, DIRBLOCK[dir] + int(at / 2048))
  for (i = 0; i < size; i++) STREAM[at + i] = B[i]
  return at + size
}

function file(n, uid,   extents, base, k, left, piece, aligned) {
  extents = SIZE[n] == 0 ? 0 : int((SIZE[n] + 1073739775) / 1073739776)
  base = entry(5, ICB[n], 1, SIZE[n], ceil_blocks(SIZE[n]), uid, 4228, 1, 16 * extents)
  left = SIZE[n]
  for (k = 0; k < extents; k++) {
    piece = left > 1073739776 ? 1073739776 : left
    longad(base + 16 * k, piece, DATA[n] + k * 524287, 0, 0)
    left -= piece
  }
  tag(REV >= 512 ? 266 : 261, ICB[n])
  put_block(ICB[n])
  aligned = (SIZE[n] >= 1048576) ? 1 : 0
  if (SIZE[n] > 0) printf("C\t%d\t%d\t%s\n", PSTART + DATA[n], aligned, SOURCE[n])
}
