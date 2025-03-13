const express = require('express');
const pgp = require('pg-promise')();
require('dotenv').config();
const RateLimit = require('express-rate-limit');

const app = express();
const PORT = 3000;

const cn = {
    host: process.env.db_host,
    port: 5432,
    database: "customer",
    user: process.env.db_user,
    password: process.env.db_password,
    max: 30 // use up to 30 connections

    // "types" - in case you want to set custom type parsers on the pool level
};

const db = pgp(cn); // database instance;

const limiter = RateLimit({
    windowMs: 10 * 60 * 1000, // 15 minutes
    max: 100, // max 100 requests per windowMs
  });
  
  // apply rate limiter to all requests
  app.use(limiter);

app.listen(PORT, (error) =>{
    if(!error)
        console.log("Server is Successfully Running, and App is listening on port "+ PORT)
    else 
        console.log("Error occurred, server can't start", error);
    }
);

app.get('/', (req,res) => {
    res.send("Hello World")
})

// GET method route
app.get('/customer/find', async (req, res) => {

    try {
        const data = await db.any('SELECT * FROM customer WHERE name = $1', req.query.name);
        res.send(data)
    } catch(e) {
        console.error(e)
    }
  })
  
  // POST method route
  app.post('/customer/create', async (req, res) => {

    try {
        const data = await db.one('INSERT INTO customer(name) VALUES($1) RETURNING id', req.query.name);
        res.send(data)
    } catch(e) {
        console.error(e)
    }

  })
  