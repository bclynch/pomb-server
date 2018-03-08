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
  host: process.env.DATABASE_ADDRESS,
  port: 5432,
  user: process.env.DATABASE_USER,
  password: process.env.DATABASE_PASSWORD,
  database: process.env.DATABASE_NAME
}

const pool = process.env.NODE_ENV === 'production' ? new pg.Pool(rdsConfig) : new pg.Pool(localConfig);
let myClient;

module.exports = {
  query: (text, params, callback) => {
    return pool.query(text, params, callback)
  }
}