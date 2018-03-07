const pg = require('pg');
const PGUSER = 'pomb_admin';
const PGDATABASE = 'bclynch';

const localConfig = {
  user: PGUSER, // name of the user account
  database: PGDATABASE, // name of the database
  max: 10, // max number of clients in the pool
  idleTimeoutMillis: 30000 // how long a client is allowed to remain idle before being closed
};

const rdsConfig = {
  host: 'packonmyback.ctpiabtaap4u.us-west-1.rds.amazonaws.com',
  port: 5432,
  user: 'pomb_admin',
  password: 'abc123',
  database: 'packonmyback_production'
}

const pool = new pg.Pool(rdsConfig);
let myClient;

module.exports = {
  query: (text, params, callback) => {
    return pool.query(text, params, callback)
  }
}