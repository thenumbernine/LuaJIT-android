package io.github.thenumbernine.LuaJIT;

import java.io.File;
import java.io.FileOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.io.IOException;
import android.os.Bundle;
import android.content.Intent;
import android.content.res.Configuration;
import android.view.KeyEvent;

public class Activity extends android.app.Activity {
	static {
		System.loadLibrary("luajit");
		System.loadLibrary("main");
	}

	public long L = 0L;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);

		// make sure main exists
		try {
			File filesDir = getFilesDir();
			File mainFile = new File(filesDir, "main.lua");
			if (!mainFile.exists()) {
				InputStream is = getAssets().open("main.lua");
				FileOutputStream os = new FileOutputStream(mainFile);

				byte[] buf = new byte[1024];
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

		luajitCall("onCreate");
	}

	@Override
	protected void onPause() {
		super.onPause();
		luajitCall("onPause");
	}

   	@Override
	protected void onResume() {
		super.onResume();
		luajitCall("onResume");
	}

	@Override
	protected void onStart() {
		super.onStart();
		luajitCall("onStart");
	}

   	@Override
	protected void onStop() {
		super.onStop();
		luajitCall("onStop");
	}

	@Override
    protected void onDestroy() {
		luajitCall("onDestroy");
		super.onDestroy();
	}

	@Override
    public void onWindowFocusChanged(boolean hasFocus) {
        if (hasFocus) {
			luajitCall("onFocus");
		} else {
			luajitCall("onBlur");
		}

		super.onWindowFocusChanged(hasFocus);
	}

	@Override
    public void onTrimMemory(int level) {
		luajitCall("onTrimMemory");
		super.onTrimMemory(level);
	}

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
		luajitCall("onConfigurationChanged");
		super.onConfigurationChanged(newConfig);
	}


	@Override
    public void onBackPressed() {
		luajitCall("onBackPressed");
		super.onBackPressed();
	}

	@Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
		luajitCall("onActivityResult");
        super.onActivityResult(requestCode, resultCode, data);
	}

	@Override
    public boolean dispatchKeyEvent(KeyEvent event) {
		luajitCall("dispatchKeyEvent");
		return super.dispatchKeyEvent(event);
	}

	@Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
		luajitCall("onRequestPermissionsResult");
		super.onRequestPermissionsResult(requestCode, permissions, grantResults);
	}

	public void luajitCall(String msg) {
		if (L == 0L) {
			File filesDir = getFilesDir();
			L = nativeLuajitInit(filesDir.getAbsolutePath());
		}
		nativeLuajitCall(L, msg);
	}

	public native long nativeLuajitInit(String wd);
	public native void nativeLuajitCall(long L, String msg);

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
