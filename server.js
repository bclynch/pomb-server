const express = require('express'),
bodyParser = require('body-parser'),
cors = require('cors'),
morgan = require('morgan'),
app = express(),
router = express.Router(),
{ postgraphile } = require("postgraphile"),
PostGraphileConnectionFilterPlugin = require('postgraphile-plugin-connection-filter');

app.use(bodyParser.json({limit: '50mb'}));
app.set('port', process.env.PORT || 5000);
app.use(cors()); // CORS (Cross-Origin Resource Sharing) headers to support Cross-site HTTP requests

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
  graphqlRoute: '/api/graphql',
  graphiqlRoute: '/api/graphiql',
  appendPlugins: [PostGraphileConnectionFilterPlugin],
  jwtSecret: 'some-secret',
  jwtPgTypeIdentifier: 'pomb.jwt_token'
};
// dev wiring
// app.use(postgraphile(pgConnection, ['pomb','pomb_private'], postgraphqlConfig));

// prod wiring
app.use(postgraphile('postgresql://pomb_admin:abc123@packonmyback.ctpiabtaap4u.us-west-1.rds.amazonaws.com:5432/packonmyback', ['pomb','pomb_private'], postgraphqlConfig)); // pgDefaultRole: 'bclynch'

// logging
app.use(morgan('combined'));

//routes
router.use('/upload-images', require('./imageProcessing'));
router.use('/process-gpx', require('./gpxProcessing'));
router.use('/analytics', require('./analytics'));
router.use('/mailing', require('./emails'));

// api mount path
app.use('/api', router); 

// Initialize the app.
app.listen(app.get('port'), 'localhost', () => console.log('You\'re a wizard, Harry. I\'m a what? Yes, a wizard, on port', app.get('port')) );