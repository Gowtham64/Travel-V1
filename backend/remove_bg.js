const { Jimp } = require('jimp');
const fs = require('fs');
const path = require('path');

const intToRGBA = (val) => {
  return {
    r: (val >> 24) & 0xff,
    g: (val >> 16) & 0xff,
    b: (val >> 8) & 0xff,
    a: val & 0xff
  };
};

const rgbaToInt = (r, g, b, a) => {
  return ((r << 24) | (g << 16) | (b << 8) | a) >>> 0;
};

async function processImage(inputPath, outputPath) {
  console.log(`Reading image from: ${inputPath}`);
  const image = await Jimp.read(inputPath);
  const width = image.bitmap.width;
  const height = image.bitmap.height;

  // Visited array for flood-fill
  const visited = new Uint8Array(width * height);
  const queue = [];

  // Helper to get index
  const getIdx = (x, y) => y * width + x;

  // Add all border pixels to start flood-fill
  for (let x = 0; x < width; x++) {
    queue.push([x, 0]);
    queue.push([x, height - 1]);
    visited[getIdx(x, 0)] = 1;
    visited[getIdx(x, height - 1)] = 1;
  }
  for (let y = 0; y < height; y++) {
    queue.push([0, y]);
    queue.push([width - 1, y]);
    visited[getIdx(0, y)] = 1;
    visited[getIdx(width - 1, y)] = 1;
  }

  // Flood fill criteria: color is similar to the white background
  const isBackground = (r, g, b) => {
    // Solid white or very close to it
    if (r > 235 && g > 235 && b > 235) {
      return true;
    }
    return false;
  };

  // Perform flood-fill
  let head = 0;
  while (head < queue.length) {
    const [cx, cy] = queue[head++];
    
    // Get color of current pixel
    const color = intToRGBA(image.getPixelColor(cx, cy));
    if (!isBackground(color.r, color.g, color.b)) {
      continue;
    }

    // Neighbors (4-connectivity)
    const neighbors = [
      [cx - 1, cy],
      [cx + 1, cy],
      [cx, cy - 1],
      [cx, cy + 1]
    ];

    for (const [nx, ny] of neighbors) {
      if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
        const nidx = getIdx(nx, ny);
        if (!visited[nidx]) {
          visited[nidx] = 1;
          queue.push([nx, ny]);
        }
      }
    }
  }

  // Now make all visited background pixels transparent
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const idx = getIdx(x, y);
      if (visited[idx]) {
        const color = intToRGBA(image.getPixelColor(x, y));
        if (isBackground(color.r, color.g, color.b)) {
          image.setPixelColor(rgbaToInt(0, 0, 0, 0), x, y);
        }
      }
    }
  }

  // Find bounding box of non-transparent pixels
  let minX = width, maxX = 0, minY = height, maxY = 0;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const color = intToRGBA(image.getPixelColor(x, y));
      if (color.a > 0) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (maxX >= minX && maxY >= minY) {
    // Crop image with padding
    const padding = 15;
    const cropX = Math.max(0, minX - padding);
    const cropY = Math.max(0, minY - padding);
    const cropW = Math.min(width - cropX, (maxX - minX) + padding * 2);
    const cropH = Math.min(height - cropY, (maxY - minY) + padding * 2);
    image.crop({ x: cropX, y: cropY, w: cropW, h: cropH });
  }

  // Resize to a standard icon size (128x128)
  image.resize({ w: 128, h: 128 });

  // Ensure destination directory exists
  const destDir = path.dirname(outputPath);
  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(destDir, { recursive: true });
  }

  await image.write(outputPath);
  console.log(`Successfully processed image and saved to: ${outputPath}`);
}

const args = process.argv.slice(2);
const input = args[0] || '/Users/gowtham/.gemini/antigravity-ide/brain/ffa31bfd-8be9-4d92-a825-72198b69fbba/isometric_car_1784359964292.png';
const output = args[1] || '/Users/gowtham/Downloads/travel-app/mobile/assets/images/isometric_car.png';

processImage(input, output).catch(err => {
  console.error(err);
  process.exit(1);
});
