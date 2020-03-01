const express = require('express'),
bodyParser = require('body-parser'),
compression = require('compression'),
cors = require('cors'),
fs = require('fs'),
morgan = require('morgan'),
app = express(),
email = require('./ses'),
router = express.Router(),
{ postgraphile } = require("postgraphile"),
PostGraphileConnectionFilterPlugin = require('postgraphile-plugin-connection-filter');
require('dotenv').config();

app.use(bodyParser.json({ limit: '50mb' }));
app.use(bodyParser.urlencoded({ limit: '50mb', extended: true, parameterLimit: 50000 }));
app.set('port', process.env.PORT || 5000);
app.use(compression()); // compress all responses
app.use(cors()); // CORS (Cross-Origin Resource Sharing) headers to support Cross-site HTTP requests

/**
 * PostgraphQL
 */
const pgConnection = {
  host: 'localhost',
  user: process.env.DATABASE_USER,
  password: process.env.DATABASE_PASSWORD,
  database: 'bclynch',
  port: 5432
};
const postgraphqlConfig = {
  graphiql: true,
  graphqlRoute: '/api/graphql',
  graphiqlRoute: '/api/graphiql',
  appendPlugins: [PostGraphileConnectionFilterPlugin],
  jwtSecret: process.env.JWT_SECRET,
  jwtPgTypeIdentifier: 'pomb.jwt_token',
  enhanceGraphiql: true,
};

// choose correct postgraphile depending on env
if (process.env.NODE_ENV === 'production') {
  app.use(postgraphile(`postgresql://${process.env.DATABASE_USER}:${process.env.DATABASE_PASSWORD}@${process.env.DATABASE_ADDRESS}:5432/${process.env.DATABASE_NAME}`, ['pomb','pomb_private'], postgraphqlConfig));
} else {
  app.use(postgraphile(pgConnection, ['pomb','pomb_private'], postgraphqlConfig));
}

//set up the logger
var accessLogStream = fs.createWriteStream(__dirname + '/access.log', {flags: 'a'})
app.use(morgan('combined',  { "stream": accessLogStream }));

//routes
router.use('/upload-images', require('./imageProcessor'));
router.use('/process-gpx', require('./gpxProcessing'));
// router.use('/analytics', require('./analytics'));
// router.use('/mailing', require('./emails'));

// email testing
// email.sendEmail();

// api mount path
app.use('/api', router); 

// Initialize the app.
app.listen(app.get('port'), 'localhost', () => console.log(`You're a wizard, Harry. I'm a what? Yes, a wizard. Spinning up ${process.env.NODE_ENV === 'production' ? 'production' : 'dev'} on port`, app.get('port')) );