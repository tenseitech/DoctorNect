const fs = require('fs');
const funcs = JSON.parse(fs.readFileSync('scripts/security_definer_functions_report.json', 'utf8'));
console.log('Total Security Definer functions:', funcs.length);

for (let i = 0; i < funcs.length; i++) {
  const f = funcs[i];
  const acl = f.acl ? (Array.isArray(f.acl) ? f.acl.join(', ') : String(f.acl)) : 'PUBLIC default';
  const hasAnon = acl.includes('anon=') || acl.includes('PUBLIC') || !f.acl;
  const hasPublic = acl.includes('PUBLIC') || !f.acl;
  const searchPathSet = Boolean(f.config && f.config.some(c => c.startsWith('search_path=')));
  console.log(`${i + 1}. ${f.schema}.${f.name}(${f.args})`);
  console.log(`   search_path: ${searchPathSet ? 'SET' : 'NOT SET'} | ACL: ${acl}`);
}
