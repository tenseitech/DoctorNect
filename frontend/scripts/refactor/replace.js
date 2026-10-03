const fs = require('fs');
const path = require('path');

function walk(dir) {
    let results = [];
    if (!fs.existsSync(dir)) return results;
    const stat = fs.statSync(dir);
    if (stat.isFile()) return [dir];
    
    const list = fs.readdirSync(dir);
    list.forEach(file => {
        file = path.join(dir, file);
        const stat = fs.statSync(file);
        if (stat && stat.isDirectory()) { 
            results = results.concat(walk(file));
        } else { 
            results.push(file);
        }
    });
    return results;
}

const files = [...walk('lib'), ...walk('web'), 'ios/Runner/Info.plist', 'android/app/src/main/AndroidManifest.xml'];
let replaced = 0;

files.forEach(f => {
    if (f.endsWith('.dart') || f.endsWith('.html') || f.endsWith('.json') || f.endsWith('.plist') || f.endsWith('.xml')) {
        const content = fs.readFileSync(f, 'utf8');
        if (content.includes('Medibond')) {
            const newContent = content.split('Medibond').join('DoctorNect');
            fs.writeFileSync(f, newContent, 'utf8');
            replaced++;
            console.log('Replaced in ' + f);
        }
    }
});
console.log('Total files replaced: ' + replaced);
