const pg = require('pg');
const PGUSER = 'pomb_admin';
const PGDATABASE = 'bclynch';

const config = {
  user: PGUSER, // name of the user account
  database: PGDATABASE, // name of the database
  max: 10, // max number of clients in the pool
  idleTimeoutMillis: 30000 // how long a client is allowed to remain idle before being closed
};

const pool = new pg.Pool(config);
let myClient;

module.exports = {
  query: (text, params, callback) => {
    return pool.query(text, params, callback)
  }
}