const express = require('express'),
router = express.Router(),
google = require('googleapis')
key = require('./config/analytics.json');
require('dotenv').config();

// auth the google analytics connection
let analytics;
let jwtClient = new google.auth.JWT(
  key.client_email, null, key.private_key,
  ['https://www.googleapis.com/auth/analytics.readonly'], null);
jwtClient.authorize((err, tokens) => {
  if (err) {
    console.log(err);
    return;
  }
  analytics = google.analytics('v3');
});

// Route 
router.get("/getViews", (req, res) => {
  const path = req.query.path;
  queryPageViews(path, res);
});

function queryPageViews(path, res) {
  analytics.data.ga.get({
    'auth': jwtClient,
    'ids': process.env.ANALYTICS_VIEW_ID,
    'metrics': 'ga:pageviews',
    'dimensions': 'ga:pagePath',
    'start-date': '30daysAgo',
    'end-date': 'today',
    'filters': `ga:pagePath==${path}`,
    'max-results': 1
  }, (err, response) => {
    if (err) {
      console.log(err);
      return;
    }
    res.send(JSON.stringify({views: response.data.totalsForAllResults['ga:pageviews']}));
  });  
}

module.exports = router;