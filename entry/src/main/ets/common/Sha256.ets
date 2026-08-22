function rotateRight(value: number, count: number): number {
  return (value >>> count) | (value << (32 - count));
}

function utf8Bytes(value: string): number[] {
  const bytes: number[] = [];
  for (let index: number = 0; index < value.length; index += 1) {
    let code: number = value.charCodeAt(index);
    if (code >= 0xD800 && code <= 0xDBFF && index + 1 < value.length) {
      const low: number = value.charCodeAt(index + 1);
      if (low >= 0xDC00 && low <= 0xDFFF) {
        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00);
        index += 1;
      }
    }
    if (code <= 0x7F) {
      bytes.push(code);
    } else if (code <= 0x7FF) {
      bytes.push(0xC0 | (code >>> 6));
      bytes.push(0x80 | (code & 0x3F));
    } else if (code <= 0xFFFF) {
      bytes.push(0xE0 | (code >>> 12));
      bytes.push(0x80 | ((code >>> 6) & 0x3F));
      bytes.push(0x80 | (code & 0x3F));
    } else {
      bytes.push(0xF0 | (code >>> 18));
      bytes.push(0x80 | ((code >>> 12) & 0x3F));
      bytes.push(0x80 | ((code >>> 6) & 0x3F));
      bytes.push(0x80 | (code & 0x3F));
    }
  }
  return bytes;
}

export function sha256Hex(value: string): string {
  const constants: number[] = [
    0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
    0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
    0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
    0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
    0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
    0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
    0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
    0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2
  ];
  const hash: number[] = [0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
    0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19];
  const bytes: number[] = utf8Bytes(value);
  const bitLength: number = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) {
    bytes.push(0);
  }
  for (let shift: number = 56; shift >= 0; shift -= 8) {
    bytes.push(shift >= 32 ? 0 : (bitLength >>> shift) & 0xFF);
  }

  for (let offset: number = 0; offset < bytes.length; offset += 64) {
    const words: number[] = new Array<number>(64).fill(0);
    for (let index: number = 0; index < 16; index += 1) {
      const start: number = offset + index * 4;
      words[index] = ((bytes[start] << 24) | (bytes[start + 1] << 16) |
        (bytes[start + 2] << 8) | bytes[start + 3]) >>> 0;
    }
    for (let index: number = 16; index < 64; index += 1) {
      const s0: number = rotateRight(words[index - 15], 7) ^ rotateRight(words[index - 15], 18) ^
        (words[index - 15] >>> 3);
      const s1: number = rotateRight(words[index - 2], 17) ^ rotateRight(words[index - 2], 19) ^
        (words[index - 2] >>> 10);
      words[index] = (words[index - 16] + s0 + words[index - 7] + s1) >>> 0;
    }

    let a: number = hash[0];
    let b: number = hash[1];
    let c: number = hash[2];
    let d: number = hash[3];
    let e: number = hash[4];
    let f: number = hash[5];
    let g: number = hash[6];
    let h: number = hash[7];
    for (let index: number = 0; index < 64; index += 1) {
      const upperE: number = rotateRight(e, 6) ^ rotateRight(e, 11) ^ rotateRight(e, 25);
      const choose: number = (e & f) ^ ((~e) & g);
      const first: number = (h + upperE + choose + constants[index] + words[index]) >>> 0;
      const upperA: number = rotateRight(a, 2) ^ rotateRight(a, 13) ^ rotateRight(a, 22);
      const majority: number = (a & b) ^ (a & c) ^ (b & c);
      const second: number = (upperA + majority) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + first) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (first + second) >>> 0;
    }
    hash[0] = (hash[0] + a) >>> 0;
    hash[1] = (hash[1] + b) >>> 0;
    hash[2] = (hash[2] + c) >>> 0;
    hash[3] = (hash[3] + d) >>> 0;
    hash[4] = (hash[4] + e) >>> 0;
    hash[5] = (hash[5] + f) >>> 0;
    hash[6] = (hash[6] + g) >>> 0;
    hash[7] = (hash[7] + h) >>> 0;
  }
  return hash.map((word: number): string => word.toString(16).padStart(8, '0')).join('');
}
