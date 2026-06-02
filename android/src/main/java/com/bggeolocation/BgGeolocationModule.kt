package com.bggeolocation

import com.facebook.react.bridge.ReactApplicationContext

class BgGeolocationModule(reactContext: ReactApplicationContext) :
  NativeBgGeolocationSpec(reactContext) {

  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  companion object {
    const val NAME = NativeBgGeolocationSpec.NAME
  }
}
