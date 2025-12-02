import sharp from 'sharp';
import fs from 'fs';
import https from 'https';

// Download image from URL
async function downloadImage(url, destPath) {
  return new Promise((resolve, reject) => {
    const proto = url.startsWith('https') ? https : require('http');
    const file = fs.createWriteStream(destPath);
    proto.get(url, (response) => {
      if (response.statusCode === 301 || response.statusCode === 302) {
        downloadImage(response.headers.location, destPath).then(resolve).catch(reject);
        return;
      }
      response.pipe(file);
      file.on('finish', () => { file.close(); resolve(destPath); });
    }).on('error', reject);
  });
}

async function getPixelData(imagePath) {
  const { data, info } = await sharp(imagePath)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  return { data, width: info.width, height: info.height };
}

function calculateSSD(fullpageData, templateData, startY) {
  const fw = fullpageData.width;
  const tw = templateData.width;
  const th = templateData.height;
  const maxX = Math.floor(tw * 0.5);
  const sampleStep = 4;

  let totalDiff = 0;
  let sampleCount = 0;

  for (let ty = 80; ty < th; ty += sampleStep) {
    for (let tx = 0; tx < maxX; tx += sampleStep) {
      const tIdx = (ty * tw + tx) * 4;
      const fIdx = ((startY + ty) * fw + tx) * 4;
      for (let c = 0; c < 3; c++) {
        const diff = fullpageData.data[fIdx + c] - templateData.data[tIdx + c];
        totalDiff += diff * diff;
      }
      sampleCount++;
    }
  }
  return totalDiff / (sampleCount * 255 * 255 * 3);
}

async function main() {
  // Download template
  const templateUrl = 'https://cdn.feedbucket.app/images/XqhBoHoY7AcqohHKHXTC3mfyfztkyb0JZctehND5.jpeg';
  await downloadImage(templateUrl, '/tmp/template_debug.jpg');

  const fullpage = await getPixelData('/tmp/test-fullpage-socks.png');
  const template = await getPixelData('/tmp/template_debug.jpg');

  console.log(`Fullpage: ${fullpage.width}x${fullpage.height}`);
  console.log(`Template: ${template.width}x${template.height}`);

  // Check specific positions
  const positions = [0, 100, 500, 1000, 2000, 3000, 4000, 4080, 4200, 5000];

  console.log('\nSSD scores at different Y positions:');
  for (const y of positions) {
    if (y + template.height <= fullpage.height) {
      const score = calculateSSD(fullpage, template, y);
      const confidence = (1 - score) * 100;
      console.log(`Y=${y}: score=${score.toFixed(4)}, confidence=${confidence.toFixed(1)}%`);
    }
  }
}

main();
