# Welcome to StatSync!

Welcome to the pilot program for StatSync! StatSync is a tool that connects your R statistical analyses directly to your Microsoft Word documents. No more copy-pasting values or manually updating tables when your data changes.

This guide will walk you through setting up StatSync on your university-managed laptop and using its core features.

---

## 1. Installation

To get started, we need to install two things: the StatSync Add-in for Word, and the StatSync package for R.

### Step 1: Install the StatSync Add-in for Word

Depending on your computer and the version of Word you are using, follow the instructions below. 

> [!NOTE]
> Because university laptops often have restricted app stores, we will "sideload" the add-in using a manifest file provided by the project lead (`statsync_manifest_beta.xml`). 

#### Option A: Word Online (Works on any OS, Easiest)
If you use Word through your web browser, follow these steps:
1. Log in to [Office.com](https://office.com) with your university account and open a blank document in **Word Online**.
2. Click the **Insert** tab in the ribbon.
3. Click **Add-ins** (or click the three dots `...` and choose **Add-ins**).
4. In the dialog, click **Upload My Add-in** in the top-right.
5. Click **Browse**, select the `statsync_manifest_beta.xml` file, and click **Upload**.
6. The green **StatSync** button will appear in your ribbon!

#### Option B: Word for Mac (Desktop)
1. Open **Finder** on your Mac.
2. Press `Cmd + Shift + G` (or click **Go > Go to Folder...** in the top Apple menu bar).
3. Paste the following path exactly and press Enter:
   `~/Library/Containers/com.microsoft.Word/Data/Documents/`
4. Look for a folder named **`wef`** in this directory. If it does not exist, right-click, create a new folder, and name it `wef`.
5. Copy the **`statsync_manifest_beta.xml`** file you received and paste it inside the `wef` folder.
6. Open **Microsoft Word for Mac**.
7. Go to the **Home** tab, click **Add-ins**, and click **StatSync** under the **Developer Add-ins** section.

#### Option C: Word for Windows (Desktop)
1. Open your **Documents** folder and create a new folder named **`OfficeAddins`**.
2. Copy the **`statsync_manifest_beta.xml`** file and paste it inside this `OfficeAddins` folder.
3. Right-click the `OfficeAddins` folder, select **Properties**, go to the **Sharing** tab, and click **Share...**.
4. Select your username (or "Everyone"), click **Add**, then click **Share**. Copy the resulting **Network Path** (e.g., `\\YOUR-LAPTOP\OfficeAddins`).
5. Open desktop **Word for Windows**.
6. Click **File > Options > Trust Center > Trust Center Settings... > Trusted Add-in Catalogs**.
7. In the **Catalog URL** box, paste the Network Path, click **Add Catalog**, and check the **Show in Menu** checkbox next to it.
8. Click **OK**, restart Microsoft Word, and navigate to **Insert > My Add-ins > Shared Folder** to select and load **StatSync**.

### Step 2: Install the StatSync R Package

Open **RStudio** and run the following command in the console to install the R package. (Note: the project lead will provide you with the exact GitHub repository name or an authentication token if the repository is private).

```R
# Install the remotes package if you don't have it
if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")

# Install StatSync directly from GitHub
remotes::install_github("your-github-username/statsync")
```

---

## 2. Connecting R to Word

StatSync works by creating a bridge between your R session and your Word document. 

1. **Start the StatSync Server in R:**
   In your R script, load the library and run `sync_serve()` with your project name. This function continuously runs in the background, listening for new statistical objects you export.
   ```R
   library(statsync)
   
   # Start the server for your current project
   sync_serve(project_name = "My Pilot Study")
   ```

2. **Connect in Word:**
   - Click the StatSync Add-in button in the Word ribbon to open the taskpane.
   - You should see the connection status switch to **Connected** when R is running. If it still says **Offline**, you can click it and then press **Connect** to manually initiate the connection.

---

## 3. The Core Features

### Exporting Statistics from R
In your R script, use the `sync_export()` function to send your statistical results (t-tests, ANOVAs, correlation matrices, linear and linear mixed models, etc.) to Word. StatSync automatically formats the results into APA style!

The `sync_export()` function is your multi-purpose tool for getting models into StatSync. You can use it for:
1. **Initial Export**: Adding a new model to your project for the first time.
2. **Updating**: Automatically replacing an existing model if you run the code again after your data changes.
3. **File Backups**: Passing a `file = "..."` argument to dump your entire active session memory into a single portable JSON file for safe keeping.

```R
# Example 1: Export one or more models to the live server at the same time
ttest_result <- t.test(mpg ~ am, data = mtcars)
anova_result <- aov(mpg ~ cyl, data = mtcars)

sync_export(
  # The 'label' argument sets the display name shown in the Word taskpane
  sync_stats(ttest_result, label = "T-test for MPG by Transmission"),
  sync_stats(anova_result, label = "ANOVA for MPG by Cylinders")
)

# Example 2: Snapshot your entire active server session to a file
sync_export(file = "C:/Users/Tyrone/Desktop/backup.json")
```

### Inserting Statistics into Word
1. In the StatSync Word taskpane, make sure you are connected to your server and your project is active.
2. Place your cursor in the Word document where you want the statistic to appear.
3. Type `{{` to open the auto-complete menu. Select your statistic from the list (or type to search for it), and it will be inserted directly into your text in APA format!
4. **Pro Tip:** You can customize the exact elements included in the output for each statistical test (e.g., removing the p-value or effect size) by pressing the **Right Arrow** key on a specific test (not the whole model) in the auto-complete menu.

### Handling Updates and Re-Syncs
If you realize you made a mistake in your data or need to re-run your analysis, simply run the `sync_export()` command in R again with the same object name (`mpg_ttest`).
- In your Word document, any previously inserted text for `mpg_ttest` will **automatically update** to reflect the new numbers!
- If the values haven't refreshed automatically, you can manually trigger a sync by clicking **Pause Automatic Syncing** and then **Sync All Updates** in the Word taskpane.

### Multi-Project Workflows
StatSync supports working on multiple papers or projects at once. 

- Use the **Project Dropdown** at the top of the Word taskpane to switch between different workspaces.
- When you start your server in R, specify the project you want to work on (`sync_serve("Another Paper")`).
- You can dynamically switch projects without restarting the server using `sync_switch("Another Paper")`.
- You can check your current connection status and active project at any time using `sync_check()`.
- The taskpane will organize your exported statistics by project, keeping everything tidy.

> [!IMPORTANT]
> **Project Auto-Follow:** The Word Add-in is designed to automatically follow whichever project is currently active on your live R server. 
> 
> If you have multiple Word documents open and you switch the active project in your R console using `sync_serve()` or `sync_switch()`, your Word Add-ins will detect the switch and **automatically change their active project to match the server**. This means if you have a model named `mod1` in two different documents, it will update according to the project that is currently active in R, regardless of which document you are looking at.

### "Live" vs. "Offline" Modes
> [!TIP]
> StatSync saves your most recent data, so you don't always need R open to write your paper!

- **Live Mode:** When `sync_serve()` is running in R, the Word add-in is "Live". You can export new statistics and see them instantly in Word.
- **Offline Mode:** If you close R, the Word add-in goes into "Offline" mode. You can still see all your previously exported statistics in the taskpane and insert them into your document. The values are safely cached in Word. When you reopen R and run `sync_serve()`, the add-in will automatically reconnect and go back to Live Mode.

---

## Troubleshooting

- **Server won't connect:** Ensure that `sync_serve()` is running in the R console. R will be "busy" while the server is running. To stop the server and write more code, press `Esc` (Windows) or the `Stop` sign in RStudio, or run `sync_stop()`.
- **"Port 8877 is already in use" Error:** If `sync_serve()` gives this error, but `sync_stop()` says no server is running, an invisible background R session has crashed and is holding the port. Run `sync_free_port()` in your console to automatically find and kill the zombie process.
- **Values aren't updating:** Click **Pause Automatic Syncing** and then **Sync All Updates** in the Word taskpane to ensure it pulls the latest data from R.
