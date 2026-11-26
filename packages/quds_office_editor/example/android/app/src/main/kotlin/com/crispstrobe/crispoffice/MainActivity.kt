package com.crispstrobe.crispoffice

import android.util.Xml
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import org.xmlpull.v1.XmlPullParser
import org.xmlpull.v1.XmlPullParserException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "crispoffice/font-catalog")
            .setMethodCallHandler { call, result ->
                if (call.method == "availableFamilies") {
                    result.success(namedFontFamilies())
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun namedFontFamilies(): List<String> {
        val names = linkedSetOf<String>()
        // Flutter's Android font manager resolves the named families and aliases
        // from Android's font configuration. Font files alone have no such names.
        for (path in listOf(
            "/system/etc/fonts.xml",
            "/product/etc/fonts_customization.xml",
            "/vendor/etc/fonts.xml",
        )) {
            try {
                File(path).inputStream().use { stream ->
                    val parser = Xml.newPullParser()
                    parser.setInput(stream, null)
                    while (parser.next() != XmlPullParser.END_DOCUMENT) {
                        if (parser.eventType == XmlPullParser.START_TAG &&
                            (parser.name == "family" || parser.name == "alias")
                        ) {
                            parser.getAttributeValue(null, "name")?.let(names::add)
                        }
                    }
                }
            } catch (_: IOException) {
                // Optional product and vendor catalogs may be absent.
            } catch (_: XmlPullParserException) {
                // Keep catalog entries already found on this device.
            } catch (_: SecurityException) {
                // Some device builds restrict access to optional catalogs.
            }
        }
        return names.toList()
    }
}
