import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { Resvg } from "@resvg/resvg-js";

const iconSource = "tools/icon/icon.svg";
const iconTexture = "media/icon.tga";
const iconSize = 64;

const logoSource = "tools/icon/logo.svg";
const logoImage = "tools/icon/logo.png";
const logoSize = 512;

function render(svg: string, size: number) {
    return new Resvg(svg, { fitTo: { mode: "width", value: size } }).render();
}

/** Encodes premultiplied RGBA pixels as an uncompressed 32-bit TGA (bottom-left origin), which the game loads as a texture. */
export function encodeTga(pixels: Uint8Array, width: number, height: number): Uint8Array {
    const header = new Uint8Array(18);
    header[2] = 2; // uncompressed true-color
    header[12] = width & 0xff;
    header[13] = width >> 8;
    header[14] = height & 0xff;
    header[15] = height >> 8;
    header[16] = 32; // bits per pixel
    header[17] = 8; // 8 alpha bits, bottom-left origin

    const body = new Uint8Array(width * height * 4);
    for (let y = 0; y < height; y++) {
        const sourceRow = (height - 1 - y) * width * 4;
        for (let x = 0; x < width; x++) {
            const i = sourceRow + x * 4;
            const o = (y * width + x) * 4;
            const a = pixels[i + 3];
            const unpremultiply = (c: number) => (a === 0 ? 0 : Math.min(255, Math.round((c * 255) / a)));
            body[o] = unpremultiply(pixels[i + 2]);
            body[o + 1] = unpremultiply(pixels[i + 1]);
            body[o + 2] = unpremultiply(pixels[i]);
            body[o + 3] = a;
        }
    }

    const tga = new Uint8Array(header.length + body.length);
    tga.set(header);
    tga.set(body, header.length);
    return tga;
}

export async function buildIcons(repoRoot: string): Promise<void> {
    const icon = render(await readFile(path.join(repoRoot, iconSource), "utf8"), iconSize);
    await writeFile(path.join(repoRoot, iconTexture), encodeTga(icon.pixels, icon.width, icon.height));

    const logo = render(await readFile(path.join(repoRoot, logoSource), "utf8"), logoSize);
    await writeFile(path.join(repoRoot, logoImage), logo.asPng());
}

if (import.meta.main) {
    await buildIcons(path.resolve(import.meta.dir, ".."));
}
