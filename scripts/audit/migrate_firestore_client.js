const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '../../frontend/lib');

function skip(file) {
  const f = file.replace(/\\/g, '/');
  return (
    f.includes('/repositories/') ||
    f.endsWith('firestore_client.dart') ||
    f.endsWith('profile_completion_service.dart') ||
    f.endsWith('firebase_bootstrap.dart')
  );
}

function walk(dir, acc = []) {
  for (const ent of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, ent.name);
    if (ent.isDirectory()) walk(p, acc);
    else if (ent.name.endsWith('.dart')) acc.push(p);
  }
  return acc;
}

for (const f of walk(root)) {
  if (skip(f)) continue;
  let t = fs.readFileSync(f, 'utf8');
  if (!t.includes('FirebaseFirestore.instance')) continue;

  const clientPath = path.join(root, 'core/firebase/firestore_client.dart');
  const rel = path.relative(path.dirname(f), clientPath).replace(/\\/g, '/');
  const importLine = `import '${rel}';\n`;

  if (!t.includes('firestore_client.dart')) {
    const idx = t.indexOf('\n', t.indexOf('import '));
    if (idx !== -1) {
      t = t.slice(0, idx + 1) + importLine + t.slice(idx + 1);
    } else {
      t = importLine + t;
    }
  }

  t = t.replace(/FirebaseFirestore\.instance/g, 'FirestoreClient.instance');
  fs.writeFileSync(f, t);
  console.log('updated', path.relative(root, f));
}
