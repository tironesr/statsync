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
        
        // --- 1. Taskpane Screenshots ---
        const page1 = await browser.newPage();
        await page1.setViewport({ width: 350, height: 800 });
        await page1.goto('http://localhost:8080/taskpane.html', { waitUntil: 'networkidle0' });
        
        await page1.evaluate((data) => {
            window.Office = {
                context: {
                    document: {
                        settings: { get: () => 'My Pilot Study', set: () => {}, saveAsync: () => {} },
                        getFilePropertiesAsync: (cb) => cb({status: 'Failed'})
                    }
                },
                onReady: (cb) => cb({host: 'Word'})
            };
            localStorage.setItem('statsync_cached_project', JSON.stringify(data));
            localStorage.setItem('statsync_cache_My Pilot Study', JSON.stringify(data));
            localStorage.setItem('statsync_server_url', 'http://localhost:8877');
            localStorage.setItem('statsync_connection_mode', 'live'); // simulate live
        }, MOCK_DATA);
        
        await page1.reload({ waitUntil: 'networkidle0' });
        await page1.evaluate(() => { if (typeof window.initialize === 'function') window.initialize(); });
        await new Promise(resolve => setTimeout(resolve, 1500));
        
        // 1a. word_taskpane_real.png
        await page1.screenshot({ path: path.join(__dirname, '../word_taskpane_real.png') });
        console.log('Saved word_taskpane_real.png');
        
        // 1b. table_insert_ui_real.png
        await page1.evaluate(() => {
            const tablesPanel = document.getElementById('tables-panel');
            if (tablesPanel) {
                // hide models-panel to bring tables up
                const modelsPanel = document.getElementById('models-panel');
                if (modelsPanel) modelsPanel.style.display = 'none';
            }
        });
        await new Promise(resolve => setTimeout(resolve, 500));
        await page1.screenshot({ path: path.join(__dirname, '../table_insert_ui_real.png') });
        console.log('Saved table_insert_ui_real.png');
        await page1.close();
        
        // --- 2. Dialog Screenshots ---
        const page2 = await browser.newPage();
        await page2.setViewport({ width: 300, height: 400 });
        await page2.goto('http://localhost:8080/dialog.html', { waitUntil: 'networkidle0' });
        
        await page2.evaluate((data) => {
            window.Office = {
                context: { ui: { messageParent: () => {} } },
                onReady: (cb) => cb({host: 'Word'})
            };
            localStorage.setItem('statsync_dialog_data', JSON.stringify(data.statistics));
            localStorage.setItem('statsync_dialog_prefill', 'mpg');
        }, MOCK_DATA);
        
        await page2.reload({ waitUntil: 'networkidle0' });
        await page2.evaluate(() => { if (typeof window.initialize === 'function') window.initialize(); });
        await new Promise(resolve => setTimeout(resolve, 1500));
        
        // 2a. autocomplete_ui_real.png
        await page2.screenshot({ path: path.join(__dirname, '../autocomplete_ui_real.png') });
        console.log('Saved autocomplete_ui_real.png');
        
        // 2b. custom_formatting_ui_real.png
        await page2.evaluate(() => {
            // simulate ArrowRight to open config view
            const items = Array.from(document.querySelectorAll('.dialog-substat'));
            if (items.length > 0) {
                const statId = items[0].getAttribute('data-stat-id');
                // We have findStatById and openConfigView but they aren't globally exposed.
                // We'll simulate click instead? Click on list item triggers default insert!
                // Wait, keyboard nav arrow right triggers it. Let's dispatch keyboard event.
            }
        });
        
        // alternative: we can't easily trigger the exact right arrow logic if window variables aren't exposed.
        // Let's just dispatch KeyboardEvent.
        await page2.keyboard.press('ArrowDown');
        await page2.keyboard.press('ArrowRight');
        await page2.keyboard.press('ArrowDown');
        await page2.keyboard.press('ArrowRight'); // Enter config mode for the substat
        
        await new Promise(resolve => setTimeout(resolve, 1000));
        await page2.screenshot({ path: path.join(__dirname, '../custom_formatting_ui_real.png') });
        console.log('Saved custom_formatting_ui_real.png');
        
        await browser.close();
    } catch (e) {
        console.error(e);
    } finally {
        server.close();
        process.exit(0);
    }
});
