const express = require('express'),
bodyParser = require('body-parser'),
cors = require('cors'),
app = express(),
postgraphql = require('postgraphql').postgraphql;

app.use(bodyParser.json({limit: '50mb'}));
app.set('port', process.env.PORT || 8080);
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
  jwtSecret: 'some-secret', 
  jwtPgTypeIdentifier: 'pomb.jwt_token'
};
app.use(postgraphql(pgConnection, ['pomb','pomb_private'], postgraphqlConfig));
// app.use(postgraphql('postgresql://laze_anonymous:abc123@laze.c0up3bfsdxiy.us-east-1.rds.amazonaws.com:5432/laze?sslmode=require&ssl=1', ['laze','laze_private'], {graphiql: true, jwtSecret: new Buffer('some-secret', 'base64'), jwtPgTypeIdentifier: 'laze.jwt_token'})); // pgDefaultRole: 'bclynch'
// app.use(postgraphql('postgres://pomb_admin:abc123@localhost:5432/bclynch', ['pomb','pomb_private'], {graphiql: true, jwtSecret: 'some-secret', jwtPgTypeIdentifier: 'pomb.jwt_token'}));

//routes
app.use('/upload-images', require('./imageProcessing'));
app.use('/process-gpx', require('./gpxProcessing'));
app.use('/analytics', require('./analytics'));
app.use('/mailing', require('./emails'));

// Initialize the app.
app.listen(app.get('port'), () => console.log("You're a wizard, Harry. I'm a what? Yes, a wizard, on port", app.get('port')) );