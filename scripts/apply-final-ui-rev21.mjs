import fs from 'node:fs'
import path from 'node:path'

const repo = process.cwd()
const mainPath = path.join(repo, 'src', 'main.jsx')
const indexPath = path.join(repo, 'index.html')

function fail(message) {
  console.error(`FAIL ${message}`)
  process.exit(1)
}

if (!fs.existsSync(mainPath)) fail('src/main.jsx not found')
if (!fs.existsSync(indexPath)) fail('index.html not found')

let main = fs.readFileSync(mainPath, 'utf8')
if (!main.includes("./styles/finalRev20.css")) {
  fail('REV20 import marker missing from src/main.jsx')
}
if (!main.includes("./styles/finalRev21.css")) {
  main = main.replace(
    "import './styles/finalRev20.css'",
    "import './styles/finalRev20.css'\nimport './styles/finalRev21.css'"
  )
  fs.writeFileSync(mainPath, main, 'utf8')
  console.log('PASS finalRev21.css import added')
} else {
  console.log('PASS finalRev21.css import already present')
}

let html = fs.readFileSync(indexPath, 'utf8')
if (!html.includes('family=Poppins')) {
  const fontBlock = `  <link rel="preconnect" href="https://fonts.googleapis.com">\n  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n  <link href="https://fonts.googleapis.com/css2?family=Poppins:wght@400;500;600;700;800&display=swap" rel="stylesheet">\n`

  if (html.includes('</head>')) {
    html = html.replace('</head>', `${fontBlock}</head>`)
  } else {
    fail('index.html has no </head> marker')
  }
  fs.writeFileSync(indexPath, html, 'utf8')
  console.log('PASS Poppins font links added')
} else {
  console.log('PASS Poppins font links already present')
}
