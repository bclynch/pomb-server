require('dotenv').config();
// const ses = require('node-ses'),
// client = ses.createClient({ key: process.env.AWS_ACCESS_KEY_ID, secret: process.env.AWS_SECRET_ACCESS_KEY });
const nodemailer = require('nodemailer'); 
const ses = require('nodemailer-ses-transport');
const aws = require('aws-sdk');
const fs = require('fs');

// var mailOptions = {
//   from: 'bot@packonmyback.com',
//   to: 'bclynch7@gmail.com',
//   text: 'This is some text',
//   html: '<b>This is some HTML</b>',
// };
// function callback(error, info) {
//   if (error) {
//     console.log(error);
//   } else {
//     console.log('Message sent: ' + info.response);
//   }
// }

// module.exports.sendEmail = function sendEmail() {
//   // Send e-mail using AWS SES
//   mailOptions.subject = 'Nodemailer SES transporter';
//   var sesTransporter = nodemailer.createTransport(ses({
//     accessKeyId: process.env.AWS_ACCESS_KEY_ID,
//     secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
//     region: 'us-east-1'
//   }));
//   sesTransporter.sendMail(mailOptions, callback);
// }

// Send e-mail using SMTP
// mailOptions.subject = 'Nodemailer SMTP transporter';
// var smtpTransporter = nodemailer.createTransport({
//   port: 465,
//   host: 'email-smtp.us-west-2.amazonaws.com',
//   secure: true,
//   auth: {
//     user: process.env.AWS_ACCESS_KEY_ID,
//     pass: smtpPassword(process.env.AWS_SECRET_ACCESS_KEY),
//   },
//   debug: true
// });
// smtpTransporter.sendMail(mailOptions, callback);











// Give SES the details and let it construct the message for you.
// module.exports.sendEmail = function sendEmail() {
//   client.sendEmail({
//     to: 'bclynch7@gmail.com',
//     from: 'bot@packonmyback.com',
//     subject: 'greetings',
//     message: 'your <b>message</b> goes here'
//   }, (err, data, res) => {
//   // ...
//     console.log('ERR: ', err);
//     console.log('DATA: ', data);
//     console.log('RES: :', res);
//   });
// }

// const transporter = nodemailer.createTransport(ses({
//   accessKeyId: process.env.AWS_ACCESS_KEY_ID,
//   secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
//   region : 'us-east-1',
//   sendingRate: 1, // max 1 messages/second
//   rateLimit: 5
// }));

// let transporter = nodemailer.createTransport({
//   SES: new aws.SES({
//       apiVersion: '2010-12-01',
//       accessKeyId: process.env.AWS_ACCESS_KEY_ID,
//       secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
//       region : 'us-east-1',
//   }),
//   sendingRate: 1 // max 1 messages/second
// });

// // Push next messages to Nodemailer
// transporter.on('idle', () => {
//   while (transporter.isIdle()) {
//       transporter.sendMail();
//   }
// });

// module.exports.sendEmail = function sendEmail() {
//   const template = fs.readFileSync('./emailTemplates/POMB Welcome.html', { encoding:'utf-8' });
//   const arr = ['bclynch7@gmail.com', 'cryto85@gmail.com'];
//   arr.forEach((email) => {
//     // // send some mail
//     transporter.sendMail({
//       from: 'bot@packonmyback.com',
//       to: email,
//       subject: 'New Shit',
//       html: template,
//     }, (err, info) => {
//       console.log('ERR: ', err);
//       console.log(info.envelope);
//       console.log(info.messageId);
//     });
//   })
// }

