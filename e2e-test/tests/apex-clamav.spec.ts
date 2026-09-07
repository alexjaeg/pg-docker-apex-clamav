import { test, expect, Page } from '@playwright/test';
import { execSync } from 'child_process';
import * as path from 'path';
import * as fs from 'fs';

// Configuration from environment
const BASE_URL = process.env.BASE_URL || 'http://localhost:8080';
const APEX_WORKSPACE = process.env.APEX_WORKSPACE || 'DEMO';
const APEX_USER = process.env.APEX_USER || 'DEMO_ADMIN';
const APEX_PASSWORD = process.env.APEX_PASSWORD || 'DemoPassword123!4';

// Configurable Test files directory (defaults to D:\_AVFree_ as requested)
const TEST_FILES_DIR = process.env.TEST_FILES_DIR || 'D:\\_AVFree_';
const EICAR_FILE_NAME = process.env.EICAR_FILE_NAME || 'eicar.txt';
const CLEAN_FILE_NAME = process.env.CLEAN_FILE_NAME || 'clean_sample.txt';

const EICAR_PATH = path.resolve(TEST_FILES_DIR, EICAR_FILE_NAME);
const CLEAN_PATH = path.resolve(TEST_FILES_DIR, CLEAN_FILE_NAME);

/**
 * Helper: Logs into APEX Workspace and navigates into the Sample App's upload form
 */
async function navigateToUploadForm(page: Page): Promise<Page> {
  console.log(`[E2E] Navigating to Base URL: ${BASE_URL}...`);
  await page.goto(BASE_URL);

  // 1. Handle ORDS landing page if present
  if (page.url().includes('_/landing')) {
    console.log('[E2E] On ORDS landing page. Clicking APEX [Los] button...');
    const apexGoBtn = page.locator('#apex-submit-form button.card__go-button-cdb, #apex-submit-form button[type="submit"]').first();
    await apexGoBtn.click();
    await page.waitForLoadState('networkidle');
  }

  // 2. Perform APEX Workspace Login
  if (page.url().includes('workspace-sign-in') || page.url().includes('f?p=4550')) {
    console.log(`[E2E] Performing Workspace login (Workspace: ${APEX_WORKSPACE}, User: ${APEX_USER})...`);
    const workspaceInput = page.locator('input#F4550_P1_COMPANY, input[placeholder*="Workspace" i], input[name="p_t01"]').first();
    const userInput = page.locator('input#F4550_P1_USERNAME, input[placeholder*="Username" i], input[placeholder*="Benutzer" i], input[name="p_t02"]').first();
    const passwordInput = page.locator('input#F4550_P1_PASSWORD, input[type="password"]').first();
    const signInBtn = page.locator('button:has-text("Sign In"), button:has-text("Anmelden"), button#B_SIGNIN, button[type="submit"]').first();

    await expect(workspaceInput).toBeVisible({ timeout: 15000 });
    await workspaceInput.fill(APEX_WORKSPACE);
    await userInput.fill(APEX_USER);
    await passwordInput.fill(APEX_PASSWORD);
    await signInBtn.click();
    await page.waitForURL('**/workspace/home**', { timeout: 20000 });
    console.log('[E2E] Successfully logged into APEX Workspace Home.');
  }

  // 3. Locate Sample App or install from Gallery
  const sampleAppLink = page.locator('a:has-text("Sample File Upload and Download")').first();
  if (await sampleAppLink.isVisible({ timeout: 4000 }).catch(() => false)) {
    console.log('[E2E] Found Sample App on Workspace dashboard. Opening App Builder...');
    await sampleAppLink.click();
    await page.waitForURL('**/app-builder/home**', { timeout: 15000 });
  } else {
    console.log('[E2E] Navigating to Gallery to access or install Sample App...');
    const galleryLink = page.locator('a:has-text("Gallery")').first();
    await galleryLink.click();
    await page.waitForURL('**/gallery/apps**', { timeout: 15000 });

    // Find Sample App card in gallery
    const appCard = page.locator('.a-CardView-item, .t-Card').filter({ hasText: 'Sample File Upload and Download' }).first();
    await expect(appCard).toBeVisible({ timeout: 15000 });
    const installBtn = appCard.locator('button:has-text("Install"), a:has-text("Install")').first();
    if (await installBtn.isVisible()) {
      console.log('[E2E] Installing Sample File Upload and Download app...');
      await installBtn.click();
      await page.waitForTimeout(10000);
    }
  }

  // 4. Click Run Application (Play button)
  console.log('[E2E] Clicking [Run Application] button...');
  const runBtn = page.locator('button[title*="Run Application" i], a[title*="Run Application" i], button:has-text("Run Application"), a:has-text("Run Application")').first();
  await expect(runBtn).toBeVisible({ timeout: 10000 });

  const [popupPage] = await Promise.all([
    page.context().waitForEvent('page', { timeout: 5000 }).catch(() => null),
    runBtn.click()
  ]);

  const appPage = popupPage || page;
  await appPage.waitForLoadState('networkidle');

  // 5. Handle Sample App Login if prompted
  const appUserInput = appPage.locator('input[placeholder*="Username" i], input[placeholder*="Benutzer" i], input#P9999_USERNAME, input[name="P9999_USERNAME"]').first();
  if (await appUserInput.isVisible({ timeout: 3000 }).catch(() => false)) {
    console.log('[E2E] Logging into Sample App with DEMO_ADMIN...');
    const appPwdInput = appPage.locator('input[type="password"]').first();
    const appSignInBtn = appPage.locator('button:has-text("Sign In"), button:has-text("Anmelden"), button#B_SIGNIN, button[type="submit"]').first();
    await appUserInput.fill(APEX_USER);
    await appPwdInput.fill(APEX_PASSWORD);
    await Promise.all([
      appPage.waitForNavigation({ waitUntil: 'networkidle' }).catch(() => null),
      appSignInBtn.click()
    ]);
  }

  await appPage.waitForURL('**/sample-file-upload-download/home**', { timeout: 15000 });
  console.log('[E2E] Successfully on Sample App Home page.');

  // 6. Click [+] Add File button in Recent Files region
  console.log('[E2E] Clicking [+] Add File button in Recent Files...');
  const addFileBtn = appPage.locator('button[title="Add File"], button[aria-label="Add File"]').first();
  await expect(addFileBtn).toBeVisible({ timeout: 10000 });
  await addFileBtn.click();

  await appPage.waitForURL('**/sample-file-upload-download/file**', { timeout: 15000 });
  console.log('[E2E] Successfully on File Upload Form.');

  return appPage;
}

test.describe('Oracle APEX + ClamAV Antivirus & Fail-Closed Suite', () => {

  test.beforeAll(() => {
    // Ensure test files exist
    if (!fs.existsSync(TEST_FILES_DIR)) {
      fs.mkdirSync(TEST_FILES_DIR, { recursive: true });
    }
    if (!fs.existsSync(CLEAN_PATH)) {
      fs.writeFileSync(CLEAN_PATH, 'This is a clean, benign test file for APEX ClamAV upload verification.');
    }
    if (!fs.existsSync(EICAR_PATH)) {
      fs.writeFileSync(EICAR_PATH, 'X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*');
    }
  });

  test('1. Clean file upload is verified by ClamAV and succeeds', async ({ page }) => {
    const appPage = await navigateToUploadForm(page);

    // Select Project if dropdown is present
    const projectSelect = appPage.locator('select#P12_PROJECT_ID, select[name="P12_PROJECT_ID"], select').first();
    if (await projectSelect.isVisible()) {
      await projectSelect.selectOption({ index: 1 });
    }

    // Attach clean file
    console.log(`[E2E] Uploading clean file: ${CLEAN_PATH}...`);
    const fileInput = appPage.locator('input[type="file"]').first();
    await fileInput.setInputFiles(CLEAN_PATH);

    // Submit upload
    const submitBtn = appPage.locator('button:has-text("Add File"), button.t-Button--hot').first();
    await submitBtn.click();

    // Verify successful upload
    await appPage.waitForURL('**/sample-file-upload-download/file-list**', { timeout: 15000 });
    const successAlert = appPage.locator('.t-Alert--success, .a-Notification--success, #apex_success_message').or(appPage.getByText('Action Processed')).first();
    await expect(successAlert).toBeVisible({ timeout: 10000 });
    console.log('[E2E] Clean file upload succeeded! Verified in APEX.');
  });

  test('2. EICAR virus file upload is strictly blocked by ClamAV & ORDS', async ({ page }) => {
    const appPage = await navigateToUploadForm(page);

    // Select Project if dropdown is present
    const projectSelect = appPage.locator('select#P12_PROJECT_ID, select[name="P12_PROJECT_ID"], select').first();
    if (await projectSelect.isVisible()) {
      await projectSelect.selectOption({ index: 1 });
    }

    // Attach EICAR test virus file
    console.log(`[E2E] Uploading EICAR virus file: ${EICAR_PATH}...`);
    const fileInput = appPage.locator('input[type="file"]').first();
    await fileInput.setInputFiles(EICAR_PATH);

    // Submit upload
    const submitBtn = appPage.locator('button:has-text("Add File"), button.t-Button--hot').first();
    await submitBtn.click();
    await appPage.waitForTimeout(3000);

    // Verify upload was blocked
    const bodyContent = await appPage.locator('body').innerText();
    const isBlocked = bodyContent.includes('File Infected') || bodyContent.includes('Bad Request') || bodyContent.includes('400') || bodyContent.includes('403');
    expect(isBlocked).toBeTruthy();

    // Verify the URL did NOT navigate to file-list (file was NOT saved in database)
    expect(appPage.url()).not.toContain('/file-list');
    console.log('[E2E] EICAR virus upload was STRICTLY BLOCKED by ORDS/ClamAV! (File Infected).');
  });

  test('3. Strict Fail-Closed: File upload is 100% blocked when ClamAV is offline', async ({ page }) => {
    console.log('[E2E] Stopping ClamAV daemon container to test Fail-Closed...');
    try {
      execSync('docker stop apex-clamav', { stdio: 'inherit' });
    } catch (e) {
      console.warn('Docker command warning:', e);
    }

    try {
      const appPage = await navigateToUploadForm(page);

      // Select Project if dropdown is present
      const projectSelect = appPage.locator('select#P12_PROJECT_ID, select[name="P12_PROJECT_ID"], select').first();
      if (await projectSelect.isVisible()) {
        await projectSelect.selectOption({ index: 1 });
      }

      // Try uploading a completely clean file while scanner is offline
      console.log(`[E2E] Attempting to upload clean file while ClamAV is OFFLINE...`);
      const fileInput = appPage.locator('input[type="file"]').first();
      await fileInput.setInputFiles(CLEAN_PATH);

      const submitBtn = appPage.locator('button:has-text("Add File"), button.t-Button--hot').first();
      await submitBtn.click();
      await appPage.waitForTimeout(4000);

      // Verify that upload is blocked by Fail-Closed security
      const bodyContent = await appPage.locator('body').innerText();
      const isBlocked = bodyContent.includes('File Infected') ||
                        bodyContent.includes('Bad Request') ||
                        bodyContent.includes('Internal Server Error') ||
                        bodyContent.includes('Unavailable') ||
                        bodyContent.includes('400') ||
                        bodyContent.includes('403') ||
                        bodyContent.includes('500');

      expect(isBlocked).toBeTruthy();
      expect(appPage.url()).not.toContain('/file-list');
      console.log('[E2E] Strict Fail-Closed verified! Upload blocked while ClamAV is offline.');
    } finally {
      console.log('[E2E] Restarting ClamAV container...');
      try {
        execSync('docker start apex-clamav', { stdio: 'inherit' });
        // Wait for ClamAV to be healthy
        execSync('timeout 5 >nul 2>&1 || ping -n 6 127.0.0.1 >nul', { shell: 'cmd.exe' });
      } catch (e) {
        console.warn('Docker start warning:', e);
      }
    }
  });

});
