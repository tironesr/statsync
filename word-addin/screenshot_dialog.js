const puppeteer = require('puppeteer');
const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
app.use(express.static(path.join(__dirname, 'dist')));

const MOCK_DATA = JSON.parse(fs.readFileSync(path.join(__dirname, '../stats_export_direct.json'), 'utf8'));

const server = app.listen(8080, async () => {
    try {
        const browser = await puppeteer.launch();
        const page = await browser.newPage();
        await page.setViewport({ width: 300, height: 400 }); // Autocomplete dialog is small
        
        await page.goto('http://localhost:8080/dialog.html', { waitUntil: 'networkidle0' });
        
        await page.evaluate((data) => {
            window.Office = {
                context: { ui: { messageParent: () => {} } },
                onReady: (cb) => cb({host: 'Word'})
            };
            localStorage.setItem('statsync_dialog_data', JSON.stringify(data.statistics));
            localStorage.setItem('statsync_dialog_prefill', 'mpg'); // Simulate typing "mpg"
        }, MOCK_DATA);
        
        // Reload to let dialog.ts read from localStorage
        await page.reload({ waitUntil: 'networkidle0' });
        
        // Ensure initialize runs
        await page.evaluate(() => {
            if (typeof window.initialize === 'function') {
                window.initialize();
            }
        });

        await new Promise(resolve => setTimeout(resolve, 1000));
        
        await page.screenshot({ path: path.join(__dirname, '../autocomplete_ui_real.png') });
        console.log('Saved autocomplete_ui_real.png');
        
        await browser.close();
    } catch (e) {
        console.error(e);
    } finally {
        server.close();
        process.exit(0);
    }
});
