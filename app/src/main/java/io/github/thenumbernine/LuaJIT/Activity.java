package io.github.thenumbernine.LuaJIT;

public class Activity extends android.app.Activity {
	static {
		System.loadLibrary("luajit");
		System.loadLibrary("main");
	}

	public long L = 0L;

	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
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
			File filesDir = getContext().getFilesDir();
			L = nativeLuajitInit(filesDir.getAbsolutePath());
		}
		nativeLuajitCall(L, msg);
	}

	public static native long nativeLuajitInit(String wd);
	public static native void nativeLuajitCall(long L);
}
