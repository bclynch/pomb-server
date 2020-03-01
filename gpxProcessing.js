const convertGPX = require('@mapbox/togeojson'),
fs = require('fs'),
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

// Route 
router.post("/", upload.array("uploads[]", 5), (req, res) => {
  const files = req.files;
  console.log('# FILES: ', files.length);

  let converted;
  let gpxData = {};

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

  res.send(JSON.stringify({data: gpxData}));
});

router.post("/upload", (req, routeResponse) => {

  const junctureId = +req.query.juncture;
  // save to table
  const sql = createSQLString(req.body, junctureId);
  
  db.query(sql, (err, res) => {
    if (err) routeResponse.send(JSON.stringify({response: err}));
    if (res) routeResponse.send(JSON.stringify({response: `Uploaded ${res.length - 2} coord pairs to server`}));
  });
});

function createSQLString(geoJSON, junctureId) {
  let sql = 'BEGIN; ';

  // delete sql for in case we are overriding existing juncture data
  sql += `DELETE FROM pomb.coords WHERE pomb.coords.juncture_id = ${junctureId}; `;

  // insert sql
  geoJSON.geometry.coordinates.forEach((event, i) => {
    const coordData = [ event[1], event[0], event[2] ].join(', ');
    sql += `INSERT INTO pomb.coords(juncture_id, lat, lon, elevation, coord_time) VALUES (${junctureId}, ${coordData}, '${geoJSON.properties.coordTimes[i]}'); `;
  });
  sql += 'COMMIT;'
  return sql;
}

module.exports = router;