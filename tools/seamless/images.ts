// Images for the seamless map's tools: RGBA buffers, and the formats they come in
// (the game's BLP, OpenMap's TGA) and go out as (PNG, which the game loads losslessly).

import { deflateSync, inflateSync } from "node:zlib";

/** Top-down RGBA, 8 bits a channel. */
export type Image = { width: number; height: number; rgba: Uint8Array };

export function blank(width: number, height: number): Image {
    return { width, height, rgba: new Uint8Array(width * height * 4) };
}

/** Decodes a TGA (true color, 24 or 32 bits, uncompressed or RLE). */
export function decodeTga(data: Uint8Array): Image {
    const idLength = data[0];
    const type = data[2];
    const width = data[12] | (data[13] << 8);
    const height = data[14] | (data[15] << 8);
    const bytes = data[16] / 8;
    const topDown = (data[17] & 0x20) !== 0;
    if (data[1] !== 0 || (type !== 2 && type !== 10) || (bytes !== 3 && bytes !== 4)) {
        throw new Error(`unsupported TGA: type ${type}, ${data[16]} bits`);
    }
    const pixels = new Uint8Array(width * height * 4);
    let offset = 18 + idLength;
    let count = 0;
    const put = (at: number) => {
        const o = count * 4;
        pixels[o] = data[at + 2];
        pixels[o + 1] = data[at + 1];
        pixels[o + 2] = data[at];
        pixels[o + 3] = bytes === 4 ? data[at + 3] : 255;
        count++;
    };
    while (count < width * height) {
        if (type === 2) {
            put(offset);
            offset += bytes;
            continue;
        }
        const header = data[offset++];
        const run = (header & 0x7f) + 1;
        for (let i = 0; i < run; i++) {
            put(offset);
            if (!(header & 0x80)) {
                offset += bytes;
            }
        }
        if (header & 0x80) {
            offset += bytes;
        }
    }
    const rgba = new Uint8Array(width * height * 4);
    const stride = width * 4;
    for (let y = 0; y < height; y++) {
        const from = (topDown ? y : height - 1 - y) * stride;
        rgba.set(pixels.subarray(from, from + stride), y * stride);
    }
    return { width, height, rgba };
}

function rgb565(value: number): [number, number, number] {
    return [(((value >> 11) & 31) * 255) / 31, (((value >> 5) & 63) * 255) / 63, ((value & 31) * 255) / 31];
}

/** Decodes a BLP2 texture's first mip: palettized, DXT1/3/5 or uncompressed. */
export function decodeBlp(data: Uint8Array): Image {
    if (String.fromCharCode(...data.subarray(0, 4)) !== "BLP2") {
        throw new Error("not a BLP2 texture");
    }
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    const encoding = data[8];
    const alphaDepth = data[9];
    const alphaType = data[10];
    const width = view.getUint32(12, true);
    const height = view.getUint32(16, true);
    const offset = view.getUint32(20, true);
    const size = view.getUint32(84, true);
    const body = data.subarray(offset, offset + size);
    const image = blank(width, height);
    const rgba = image.rgba;
    const count = width * height;
    if (encoding === 1) {
        const palette = data.subarray(148, 148 + 1024);
        for (let i = 0; i < count; i++) {
            const p = body[i] * 4;
            rgba[i * 4] = palette[p + 2];
            rgba[i * 4 + 1] = palette[p + 1];
            rgba[i * 4 + 2] = palette[p];
            let alpha = 255;
            if (alphaDepth === 8) {
                alpha = body[count + i];
            } else if (alphaDepth === 4) {
                alpha = ((body[count + (i >> 1)] >> ((i & 1) * 4)) & 15) * 17;
            } else if (alphaDepth === 1) {
                alpha = ((body[count + (i >> 3)] >> (i & 7)) & 1) * 255;
            }
            rgba[i * 4 + 3] = alpha;
        }
    } else if (encoding === 2) {
        const dxt = alphaType === 0 ? 1 : alphaType === 1 ? 3 : 5;
        const blockSize = dxt === 1 ? 8 : 16;
        let at = 0;
        for (let by = 0; by < height; by += 4) {
            for (let bx = 0; bx < width; bx += 4) {
                const block = body.subarray(at, at + blockSize);
                at += blockSize;
                const colorAt = dxt === 1 ? 0 : 8;
                const c0 = block[colorAt] | (block[colorAt + 1] << 8);
                const c1 = block[colorAt + 2] | (block[colorAt + 3] << 8);
                const a = rgb565(c0);
                const b = rgb565(c1);
                const four = c0 > c1 || dxt !== 1;
                const colors = [
                    a,
                    b,
                    four ? a.map((v, k) => (2 * v + b[k]) / 3) : a.map((v, k) => (v + b[k]) / 2),
                    four ? a.map((v, k) => (v + 2 * b[k]) / 3) : [0, 0, 0],
                ];
                const bits =
                    (block[colorAt + 4] |
                        (block[colorAt + 5] << 8) |
                        (block[colorAt + 6] << 16) |
                        (block[colorAt + 7] << 24)) >>>
                    0;
                const alphas = new Array<number>(16).fill(255);
                if (dxt === 3) {
                    for (let i = 0; i < 16; i++) {
                        alphas[i] = ((block[i >> 1] >> ((i & 1) * 4)) & 15) * 17;
                    }
                } else if (dxt === 5) {
                    const a0 = block[0];
                    const a1 = block[1];
                    const table = [a0, a1];
                    if (a0 > a1) {
                        for (let k = 1; k < 7; k++) table.push(((7 - k) * a0 + k * a1) / 7);
                    } else {
                        for (let k = 1; k < 5; k++) table.push(((5 - k) * a0 + k * a1) / 5);
                        table.push(0, 255);
                    }
                    let indices = 0n;
                    for (let k = 0; k < 6; k++) indices |= BigInt(block[2 + k]) << BigInt(8 * k);
                    for (let i = 0; i < 16; i++) alphas[i] = table[Number((indices >> BigInt(3 * i)) & 7n)];
                }
                for (let i = 0; i < 16; i++) {
                    const x = bx + (i & 3);
                    const y = by + (i >> 2);
                    if (x >= width || y >= height) continue;
                    const index = (bits >>> (2 * i)) & 3;
                    const color = colors[index];
                    const p = (y * width + x) * 4;
                    rgba[p] = color[0];
                    rgba[p + 1] = color[1];
                    rgba[p + 2] = color[2];
                    rgba[p + 3] = dxt === 1 ? (!four && index === 3 ? 0 : 255) : alphas[i];
                }
            }
        }
    } else if (encoding === 3) {
        for (let i = 0; i < count; i++) {
            rgba[i * 4] = body[i * 4 + 2];
            rgba[i * 4 + 1] = body[i * 4 + 1];
            rgba[i * 4 + 2] = body[i * 4];
            rgba[i * 4 + 3] = body[i * 4 + 3];
        }
    } else {
        throw new Error(`unsupported BLP encoding ${encoding}`);
    }
    return image;
}

const CRC_TABLE = (() => {
    const table = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
        let c = n;
        for (let k = 0; k < 8; k++) {
            c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
        }
        table[n] = c >>> 0;
    }
    return table;
})();

function crc32(bytes: Uint8Array): number {
    let c = 0xffffffff;
    for (const byte of bytes) {
        c = CRC_TABLE[(c ^ byte) & 0xff] ^ (c >>> 8);
    }
    return (c ^ 0xffffffff) >>> 0;
}

function chunk(type: string, body: Uint8Array): Uint8Array {
    const out = new Uint8Array(12 + body.length);
    const view = new DataView(out.buffer);
    view.setUint32(0, body.length);
    out.set(new TextEncoder().encode(type), 4);
    out.set(body, 8);
    view.setUint32(8 + body.length, crc32(out.subarray(4, 8 + body.length)));
    return out;
}

function paeth(a: number, b: number, c: number): number {
    const p = a + b - c;
    const pa = Math.abs(p - a);
    const pb = Math.abs(p - b);
    const pc = Math.abs(p - c);
    return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

/**
 * Encodes RGBA as an 8-bit RGBA PNG, losslessly: each row with the PNG filter that
 * leaves it smallest (least sum of absolute differences), deflated at level 9.
 */
export function encodePng({ width, height, rgba }: Image): Uint8Array {
    const stride = width * 4;
    const raw = new Uint8Array((stride + 1) * height);
    const candidate = new Uint8Array(stride);
    const best = new Uint8Array(stride);
    const none = new Uint8Array(stride);
    for (let y = 0; y < height; y++) {
        const row = rgba.subarray(y * stride, (y + 1) * stride);
        const up = y > 0 ? rgba.subarray((y - 1) * stride, y * stride) : none;
        let bestFilter = 0;
        let bestScore = Infinity;
        for (let filter = 0; filter < 5; filter++) {
            let score = 0;
            for (let i = 0; i < stride; i++) {
                const a = i >= 4 ? row[i - 4] : 0;
                const b = up[i];
                const c = i >= 4 ? up[i - 4] : 0;
                const predictor =
                    filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? (a + b) >> 1 : paeth(a, b, c);
                const value = (row[i] - predictor) & 0xff;
                candidate[i] = value;
                score += value < 128 ? value : 256 - value;
            }
            if (score < bestScore) {
                bestScore = score;
                bestFilter = filter;
                best.set(candidate);
            }
        }
        raw[y * (stride + 1)] = bestFilter;
        raw.set(best, y * (stride + 1) + 1);
    }
    const header = new Uint8Array(13);
    const view = new DataView(header.buffer);
    view.setUint32(0, width);
    view.setUint32(4, height);
    header.set([8, 6, 0, 0, 0], 8); // 8 bits, RGBA, deflate, adaptive filtering, no interlace
    const parts = [
        new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
        chunk("IHDR", header),
        chunk("IDAT", deflateSync(raw, { level: 9, memLevel: 9 })),
        chunk("IEND", new Uint8Array()),
    ];
    const out = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
    let offset = 0;
    for (const part of parts) {
        out.set(part, offset);
        offset += part.length;
    }
    return out;
}

/** Decodes a PNG written by encodePng (8-bit RGBA), to check the round trip. */
export function decodePng(data: Uint8Array): Image {
    const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
    let offset = 8;
    let width = 0;
    let height = 0;
    const idat: Uint8Array[] = [];
    while (offset < data.length) {
        const length = view.getUint32(offset);
        const type = new TextDecoder().decode(data.subarray(offset + 4, offset + 8));
        if (type === "IHDR") {
            width = view.getUint32(offset + 8);
            height = view.getUint32(offset + 12);
        } else if (type === "IDAT") {
            idat.push(data.subarray(offset + 8, offset + 8 + length));
        }
        offset += 12 + length;
    }
    const raw = inflateSync(Buffer.concat(idat));
    const stride = width * 4;
    const rgba = new Uint8Array(stride * height);
    for (let y = 0; y < height; y++) {
        const filter = raw[y * (stride + 1)];
        for (let i = 0; i < stride; i++) {
            const a = i >= 4 ? rgba[y * stride + i - 4] : 0;
            const b = y > 0 ? rgba[(y - 1) * stride + i] : 0;
            const c = i >= 4 && y > 0 ? rgba[(y - 1) * stride + i - 4] : 0;
            const predictor =
                filter === 0 ? 0 : filter === 1 ? a : filter === 2 ? b : filter === 3 ? (a + b) >> 1 : paeth(a, b, c);
            rgba[y * stride + i] = (raw[y * (stride + 1) + 1 + i] + predictor) & 0xff;
        }
    }
    return { width, height, rgba };
}

/** The image's channel `channel` (3: alpha) at (x, y) in its pixels, bilinear, clamped at the edges. */
export function sample(image: Image, x: number, y: number, channel: number): number {
    const fx = Math.min(Math.max(x - 0.5, 0), image.width - 1);
    const fy = Math.min(Math.max(y - 0.5, 0), image.height - 1);
    const x0 = Math.floor(fx);
    const y0 = Math.floor(fy);
    const x1 = Math.min(x0 + 1, image.width - 1);
    const y1 = Math.min(y0 + 1, image.height - 1);
    const tx = fx - x0;
    const ty = fy - y0;
    const at = (px: number, py: number) => image.rgba[(py * image.width + px) * 4 + channel];
    return (
        (at(x0, y0) * (1 - tx) + at(x1, y0) * tx) * (1 - ty) + (at(x0, y1) * (1 - tx) + at(x1, y1) * tx) * ty
    );
}
