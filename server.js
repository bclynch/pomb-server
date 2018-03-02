const express = require('express'),
bodyParser = require('body-parser'),
cors = require('cors'),
morgan = require('morgan'),
app = express(),
postgraphql = require('postgraphql').postgraphql,
PostGraphileConnectionFilterPlugin = require('postgraphile-plugin-connection-filter');

app.use(bodyParser.json({limit: '50mb'}));
app.set('port', process.env.PORT || 5000);
app.use(cors()); // CORS (Cross-Origin Resource Sharing) headers to support Cross-site HTTP requests
app.use(express.static("www")); // Our Ionic app build is in the www folder (kept up-to-date by the Ionic CLI using 'ionic serve')
//https://github.com/postgraphql/postgraphql/blob/d4fd6a4009fea75dbcaa00d743c985148050475e/docs/library.md

/**
 * PostgraphQL
 */
const pgConnection = {
  host: 'localhost',
  user: 'pomb_admin',
  password: 'abc123',
  database: 'bclynch',
  port: 5432
};
const postgraphqlConfig = {
  graphiql: true,
  appendPlugins: [PostGraphileConnectionFilterPlugin],
  jwtSecret: 'some-secret',
  jwtPgTypeIdentifier: 'pomb.jwt_token'
};
// dev wiring
// app.use(postgraphql(pgConnection, ['pomb','pomb_private'], postgraphqlConfig));

// prod wiring
app.use(postgraphql('postgresql://pomb_admin:abc123@packonmyback-production.ckqkbjo37yo6.us-east-2.rds.amazonaws.com:5432/packonmyback_production?sslmode=require&ssl=1', ['pomb','pomb_private'], postgraphqlConfig)); // pgDefaultRole: 'bclynch'

// logging
app.use(morgan('combined'));

//routes
app.use('/upload-images', require('./imageProcessing'));
app.use('/process-gpx', require('./gpxProcessing'));
app.use('/analytics', require('./analytics'));
app.use('/mailing', require('./emails'));

// Initialize the app.
app.listen(app.get('port'), 'localhost', () => console.log("You're a wizard, Harry. I'm a what? Yes, a wizard, on port", app.get('port')) );