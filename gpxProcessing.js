const convertGPX = require('@mapbox/togeojson'),
fs = require('fs'),
geolib = require('geolib'),
DOMParser = require('xmldom').DOMParser,
multer = require('multer'),
tempFolderPath = './tempFiles/',
express = require('express'),
db = require('./db/index'),
router = express.Router();

const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    cb(null, tempFolderPath)
  },
  filename: function (req, file, cb) {
    cb(null, file.originalname);
  }
});

const upload = multer({ storage });

// console.log(JSON.stringify(converted));

// let convertedTimeArr = [];
// let distanceArr = [];

// Route 
router.post("/", upload.array("uploads[]", 5), (req, res) => {
  const files = req.files;
  console.log('# FILES: ', files.length);

  let converted;
  let gpxData = {};
  const junctureId = +req.query.juncture;

  // we want to combine both the coords and the coordTimes arr of all files
  for(let i = 0; i < files.length; i++) {
    const name = files[i].originalname;
  
    const gpx = new DOMParser().parseFromString(fs.readFileSync(`${tempFolderPath}${name}`, 'utf8'));
    if(i === 0) {
      converted = convertGPX.gpx(gpx);
    } else {
      // Need to see if this data comes before the existing data in the arr or after. Check times
      const data = convertGPX.gpx(gpx);
      // if new time data < existing arr add to beginning of array
      if(Date.parse(data.features[0].properties.coordTimes[0]) < Date.parse(converted.features[0].properties.coordTimes[0])) {
        converted.features[0].properties.coordTimes = data.features[0].properties.coordTimes.concat(converted.features[0].properties.coordTimes);
        converted.features[0].geometry.coordinates = data.features[0].geometry.coordinates.concat(converted.features[0].geometry.coordinates);
      } else {
        converted.features[0].properties.coordTimes = converted.features[0].properties.coordTimes.concat(data.features[0].properties.coordTimes);
        converted.features[0].geometry.coordinates = converted.features[0].geometry.coordinates.concat(data.features[0].geometry.coordinates);
      }
    };

    fs.unlink(`${tempFolderPath}${name}`, () => console.log('deleted temp file') ); 
  }

  gpxData.geoJSON = converted.features[0];

  // We are looking at roughly 1000 data points per 20 mins or 50/min
  // Don't really want / need all the data. Lets investigate what still looks good for our mapping to find nice balance between data / visuals
  // Taking 10% of data points appears solid for now
  gpxData.geoJSON.properties.coordTimes = gpxData.geoJSON.properties.coordTimes.filter((_,i) => i % 10 == 0);
  gpxData.geoJSON.geometry.coordinates = gpxData.geoJSON.geometry.coordinates.filter((_,i) => i % 10 == 0);

  // save to table
  const sql = createSQLString(gpxData.geoJSON, junctureId);
  
  db.query(sql, (err, res) => {
    if (err) console.log(err);
    if (res) console.log(`added ${res.length - 2} coords`);
  });

  // const totalDistance = getTotalDistance(gpxData.geoJSON.geometry.coordinates);
  // console.log('TOTAL DISTANCE in kms: ', totalDistance / 1000);
  // gpxData.totalDistance = totalDistance;

  // const speeds = getSpeedArr(gpxData.geoJSON.geometry.coordinates, converted.features[0].properties.coordTimes);
  // gpxData.speedsArr = speeds;

  // gpxData.timeArr = convertedTimeArr.slice(0);
  // convertedTimeArr = [];

  // gpxData.distanceArr = distanceArr.slice(0);
  // distanceArr = [];

  res.send(JSON.stringify({data: gpxData}));
});

//take in coord arr and find total distance
function getTotalDistance(arr) {
  totalDistance = 0;

  for(let i = 0; i < arr.length; i++) {
    if(i < arr.length - 1) {
      const distance = geolib.getDistance(
        { latitude: arr[i][1], longitude: arr[i][0] },
        { latitude: arr[i + 1][1], longitude: arr[i + 1][0] }
      );

      totalDistance += distance;
      // distanceArr.push(totalDistance);
    }
  }
  //copying the last elem and pushing to end of arr so it has same count as coord arr.
  // distanceArr.splice(distanceArr.length - 1, 0, distanceArr[distanceArr.length - 1]);

  return totalDistance;
}

// function getSpeedArr(geoArr, timeArr) {
//   let speedsArr = [];
//   for(let i = 0; i < geoArr.length; i++) {
//     if(i < geoArr.length - 1) {
//       const timeToMs = Date.parse(timeArr[i]);
//       convertedTimeArr.push(timeToMs);
//       speedsArr.push(geolib.getSpeed(
//         { lat: geoArr[i][1], lng: geoArr[i][0], time: timeToMs },
//         { lat: geoArr[i + 1][1], lng: geoArr[i + 1][0], time: Date.parse(timeArr[i + 1]) }
//       ));
//     }
//   }
//   //copying the last elem and pushing to end of arr so it has same count as coord arr. Same for times
//   speedsArr.splice(speedsArr.length - 1, 0, speedsArr[speedsArr.length - 1]);
//   convertedTimeArr.splice(convertedTimeArr.length - 1, 0, convertedTimeArr[convertedTimeArr.length - 1])

//   return speedsArr;
// }

function createSQLString(geoJSON, junctureId) {
  let sql = 'BEGIN; ';
  geoJSON.geometry.coordinates.forEach((event, i) => {
    const coordData = [ event[1], event[0], event[2] ].join(', ');
    sql += `INSERT INTO pomb.coords(juncture_id, lat, lon, elevation, coord_time) VALUES (${junctureId}, ${coordData}, '${geoJSON.properties.coordTimes[i]}'); `;
  });
  sql += 'COMMIT;'
  return sql;
}

module.exports = router;