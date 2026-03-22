package io.github.thenumbernine.LuaJIT;

import java.io.File;
import java.io.FileOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.IOException;
import android.os.Bundle;
import android.os.PersistableBundle;
import android.content.Intent;
import android.content.res.Configuration;
import android.view.KeyEvent;
import android.view.Menu;

public class Activity extends android.app.Activity {
	static {
		System.loadLibrary("luajit");
		System.loadLibrary("main");
	}

	public long L = 0L;

	// public methods

	@Override
	public void onRestoreInstanceState(Bundle outState, PersistableBundle persistentState) {
		luajitCall("onRestoreInstanceState", outState, persistentState);
	}

	@Override
    public void onWindowFocusChanged(boolean hasFocus) {
		luajitCall("onWindowFocusChanged", hasFocus);
	}

	@Override
    public void onTrimMemory(int level) {
		luajitCall("onTrimMemory", level);
	}

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
		luajitCall("onConfigurationChanged", newConfig);
	}

/* "new" way that requires androidx which requires a bunch of extra bullshit jars to be downloaded
	@Override
    public android.window.OnBackInvokedDispatcher getOnBackInvokedDispatcher() {
		return (android.window.OnBackInvokedDispatcher )luajitCall("getOnBackInvokedDispatcher");
	}
*/

	@Override
	public void onBackPressed() {
		luajitCall("onBackPressed");
	}

	@Override
    public boolean dispatchKeyEvent(KeyEvent event) {
		return (Boolean)luajitCall("dispatchKeyEvent", event);
	}

	@Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
		luajitCall("onRequestPermissionsResult", requestCode, permissions, grantResults);
	}

	@Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults, int deviceId) {
		luajitCall("onRequestPermissionsResult", requestCode, permissions, grantResults, deviceId);
	}

	@Override
	public boolean onCreateOptionsMenu(Menu menu) {
		return (Boolean)luajitCall("onCreateOptionsMenu", menu);
	}

	@Override
	public boolean onCreatePanelMenu(int featureId, Menu menu) {
		return (Boolean)luajitCall("onCreatePanelMenu", featureId, menu);
	}

	@Override
	public boolean onOptionsItemSelected(android.view.MenuItem item) {
		return (Boolean)luajitCall("onOptionsItemSelected", item);
	}

	@Override
	public void onSaveInstanceState(Bundle outState, PersistableBundle outPersistentState) {
		luajitCall("onSaveInstanceState", outState, outPersistentState);
	}


	// protected methods

	@Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		luajitCall("onActivityResult", requestCode, resultCode, data);
	}

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		luajitCall("onCreate", savedInstanceState);
	}

	@Override
    protected void onDestroy() {
		luajitCall("onDestroy");
	}

	@Override
	protected void onPause() {
		luajitCall("onPause");
	}

	@Override
	protected void onRestart() {
		luajitCall("onRestart");
	}

   	@Override
	protected void onResume() {
		luajitCall("onResume");
	}

	@Override
	protected void onSaveInstanceState(Bundle outState) {
		luajitCall("onSaveInstanceState", outState);
	}

	@Override
	protected void onStart() {
		luajitCall("onStart");
	}

   	@Override
	protected void onStop() {
		luajitCall("onStop");
	}

	// the luajit<->java bootstrap interaction
	// this would be a million times easier if I could provide a class to the AndroidManifest via function instead of via xml text...

	public Object luajitCall(String msg, Object... args) {
		if (L == 0L) {
			File filesDir = getFilesDir();

			// make sure main.lua exists
			try {
				File mainFile = new File(filesDir, "main.lua");
				//if (!mainFile.exists())	// I'm always overwriting it anyways...
				{
					InputStream is = getAssets().open("main.lua");
					FileOutputStream os = new FileOutputStream(mainFile);

					byte[] buf = new byte[16384];
					int res = -1;
					while ((res = is.read(buf)) > 0) {
						os.write(buf, 0, res);
					}

					is.close();
					os.flush();
					os.close();
				}
			} catch (IOException e) {
				e.printStackTrace();
			}

			L = nativeLuajitInit(filesDir.getAbsolutePath());
		}
		return nativeLuajitCall(L, msg, args);
	}

	public native long nativeLuajitInit(String wd);
	public native Object nativeLuajitCall(long L, String msg, Object[] args);

	// api used by lua for loading bootstrap classes from assets folder:

	public boolean isAssetPathDir(String path) {
		try {
			String[] list = getAssets().list(path);
			return list.length > 0;
		} catch (IOException e) {}
		return false;
	}

	public byte[] readAssetPath(String path) {
		try {
			String[] list = getAssets().list(path);
			if (list.length != 0) {
				return String.join("\n", list).getBytes();
			} else {
				InputStream is = getAssets().open(path);

				/* doesn't work because Android is retarded
				return is.readAllBytes();
				*/
				/**/
				ByteArrayOutputStream os = new ByteArrayOutputStream();
				byte[] buf = new byte[16384];
				int res = -1;
				while ((res = is.read(buf)) > 0) {
					os.write(buf, 0, res);
				}
				is.close();
				return os.toByteArray();
				/**/
			}
		} catch (IOException e) {}
		return null;
	}
}
