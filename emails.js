const express = require('express'),
router = express.Router(),
nodemailer = require('nodemailer');

const transporter = nodemailer.createTransport({
    host: 'smtp.zoho.com',
    port: 465,
    secure: true, // use SSL
    auth: {
      user: 'bot@packonmyback.com',
      pass: 'Bear2013'
    }
});

function sendToUsers(options, usersArr) {
  return new Promise((resolve, reject) => {

    usersArr.forEach((user) => {
      const mailOptions = options;
      mailOptions['to'] = user;
      // send mail with defined transport object
      transporter.sendMail(mailOptions, (error, info) => {
        if (error) reject(error);
        console.log(info.response);
      });
    });

    // the foreach is sync so all the above will run, but the subsequent calls are async so should be good to go and can resolve here. Server will cont. doing its thing
    resolve();
  });
}

// Route 
router.post("/send-newsletter", (req, res) => {

  // setup e-mail data, even with unicode symbols
  const mailOptions = {
    from: '"Pack On My Back " <bot@packonmyback.com>', // sender address (who sends)
    subject: 'Hello ', // Subject line
    html: '<b>Hello world </b><br> This is the first email sent with Nodemailer in Node.js' // html body
  };

  const usersArr = ['bclynch7@gmail.com', 'cryto85@gmail.com'];

  sendToUsers(mailOptions, usersArr).then(
    result => res.send({ result: 'Newsletters sent' }),
    err => console.log(err)
  );
});

router.post('/reset', (req, res) => {
  const mailOptions = {
    to: req.body.user,
    from: '"Pack On My Back " <bot@packonmyback.com>',
    subject: 'Pack On My Back Password Reset',
    text: 'You are receiving this because you have requested the reset of the password for your account.\n\n' +
      'The following is your new password. Please use it to sign back in:\n\n' + req.body.pw
  };
  transporter.sendMail(mailOptions, (error, info) => {
    if (error) res.send({ error });
    console.log('MESSAGE: ', info.response);
    res.send({ result: 'Forgot email sent' })
  });
});

module.exports = router;