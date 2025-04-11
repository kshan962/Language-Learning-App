const express = require('express');
const router = express.Router();

router.post('/response', (req, res) => {
  res.json({ 
    response: 'مرحبا!\n\nHello! How can I help you practice Arabic today?' 
  });
});

module.exports = router;