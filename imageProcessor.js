///////////////////////////////////////////////////////
///////////////////Image Processor Using Sharp -- Very fast!!
///////////////////////////////////////////////////////

const aws = require('aws-sdk'),
sharp = require('sharp'),
multer = require('multer'),
upload = multer({ storage: multer.memoryStorage(), fileFilter: imageFilter }),
express = require('express'),
router = express.Router();
require('dotenv').config();

// Access key and secret id being pulled from env vars and in my drive as backup
aws.config.update({ region: process.env.AWS_REGION });
const photoBucket = process.env.NODE_ENV === 'production' ? new aws.S3({params: {Bucket: 'packonmyback-production'}}) : new aws.S3({params: {Bucket: 'packonmyback-dev'}});

//Route 
router.post("/", upload.array("uploads[]", 12), (req, res) => {
  //avail query params:
  //quality: number - between 0 - 100 **Required
  //sizes: semicolon seperated wxh i.e -> ?sizes=1220x813;320x213 **Required

  const sizes = req.query.sizes.split(';').map((size) => {
    const sizeArr = size.split('x');
    return { width: +sizeArr[0], height: +sizeArr[1] };
  });
  const quality = +req.query.quality;

  let promises = [];
  let fileType = 'jpeg';
  let S3LinksArr = [];

  console.log('files', req.files);
  req.files.forEach((file, i) => {
    let promise = new Promise((resolve, reject) => {

      resizeAndUploadImage(file, sizes, quality, fileType).then((finishedArr) => {
        console.log(`finished file ${i + 1}`);
        console.log('Processed img link arr: ', finishedArr);

        S3LinksArr = S3LinksArr.concat(finishedArr);
        resolve(); // resolve for resize img promise
      });
    });

    promises.push(promise);
  });

  // if we need a small circular version for map markers add to promise arr
  if (req.query.isJuncture === 'true') {
    const maskPromise = new Promise((resolve, reject) => {
      maskAndUploadImage(req.files[0], 128, req.files[0].originalname.split('.')[0]).then(
        (maskedImg) => {
          S3LinksArr.push(maskedImg);
          resolve();
        }
      )
    });
    promises.push(maskPromise);
  };

  console.log(promises);
  Promise.all(promises).then(() => {
    console.log('promise all complete');
    res.send(JSON.stringify(S3LinksArr));
  });
});

//Take in img file, what sizes we would like, and the quality of img
function resizeAndUploadImage(file, sizes, quality, type) {
  return new Promise((resolve, reject)=> { //promise for the overall resize img function
    let promiseArr = [];
    let finishedArr = [];

    sizes.forEach((size, i) => {
      let promise = new Promise((resolve, reject)=> { //promise for each size of the image
        sharp(file.buffer)
          .clone()
          .resize(size.width, size.height)
          .toFormat(type, { quality })
          .toBuffer()
          .then(
            buffer => {
              const key = `${file.originalname.split('.')[0]}-w${size.width}-${Date.now()}.${type}`;
              uploadToS3(buffer, key, (err, data) => {
                if (err) {
                  console.error(err)
                  reject(err);
                };
                finishedArr.push({size: size.width, url: data.Location});
                resolve();
              });
            },
            err => console.log(err)
          )
      });
      promiseArr.push(promise);
    });
    
    Promise.all(promiseArr).then(() => {
      console.log('resize img promise all complete');
      resolve(finishedArr); // resolve for resize img fn promise
    });
  });
}

///////////////////////////////////////////////////////
///////////////////Image masking
///////////////////////////////////////////////////////
// takes in file, desired size, and the img to mask with to output buffer
function maskAndUploadImage(file, size, name) {
  return new Promise((resolve, reject)=> {
    const roundedCorners = new Buffer(
      `<svg><rect x="0" y="0" width="${size}" height="${size}" rx="${size / 2}" ry="${size / 2}"/></svg>`
    );
    // resize img first
    sharp(file.buffer)
      .resize(size, size)
      .composite([{
        input: roundedCorners,
        blend: 'dest-in'
      }])
      .png()
      .toBuffer()
      .then(
        maskedImgBuffer => {
          const key = `${name}-marker-${Date.now()}.png`;
          uploadToS3(maskedImgBuffer, key, (err, data) => {
            if (err) {
              console.error(err)
              reject(err);
            };
            resolve({ size: 'marker', url: data.Location });
          });
        },
        err => console.log(err)
      )
  });
}

///////////////////////////////////////////////////////
///////////////////Save To S3
///////////////////////////////////////////////////////

function uploadToS3(buffer, destFileName, callback) {
  return new Promise((resolve, reject) => {
    photoBucket
      .upload({
          ACL: 'public-read', 
          Body: buffer,
          Key: destFileName, // file name
          ContentType: 'application/octet-stream' // force download if it's accessed as a top location
      })
      // http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3/ManagedUpload.html#httpUploadProgress-event
      // .on('httpUploadProgress', function(evt) { console.log(evt); })
      // http://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/S3/ManagedUpload.html#send-property
      .send(callback);
    });
}

function imageFilter(req, file, cb) {
  // accept image only
  if (!file.originalname.match(/\.(jpg|jpeg|png)$/)) {
      return cb(new Error('Only image files are allowed!'), false);
  }
  cb(null, true);
};

module.exports = router;