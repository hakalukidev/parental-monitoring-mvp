// Read-only count preview. Never applies TTL indexes or deletes records.
require('dotenv').config();
const mongoose = require('mongoose');
const { retentionExpiry } = require('../dist/services/retention');
(async () => {
  if (!process.env.MONGO_URI) throw new Error('Missing database configuration');
  await mongoose.connect(process.env.MONGO_URI, { autoIndex: false });
  for (const [kind, collection] of [['LOCATION', 'locationrecords'], ['BROWSING', 'browsinghistoryrecords'], ['USAGE', 'appusagereports']]) {
    const expiry = retentionExpiry(kind);
    const count = await mongoose.connection.db.collection(collection).countDocuments({ expiresAt: { $lte: new Date() } });
    console.log(`${kind}: new-record policy ${expiry ? 'enabled' : 'disabled'}; expired tagged records ${count}`);
  }
  await mongoose.disconnect();
})().catch(() => { console.error('Retention preview failed; check private database configuration.'); process.exitCode = 1; });
