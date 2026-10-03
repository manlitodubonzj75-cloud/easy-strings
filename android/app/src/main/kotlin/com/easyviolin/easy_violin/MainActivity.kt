package com.easyviolin.easy_violin

import android.Manifest
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val PERMISSION_CHANNEL = "com.easyviolin.easy_violin/permissions"
    private val AUDIO_DECODER_CHANNEL = "com.easyviolin.easy_violin/audio_decoder"
    private val PERMISSION_REQUEST_CODE = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. Permissions Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasRecordAudioPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    result.success(granted)
                }
                "requestRecordAudioPermission" -> {
                    val granted = ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.RECORD_AUDIO
                    ) == PackageManager.PERMISSION_GRANTED
                    if (granted) {
                        result.success(true)
                    } else {
                        pendingResult = result
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            PERMISSION_REQUEST_CODE
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 2. Native Audio Decoder Channel (Hardware-accelerated MediaCodec for AAC/MP3/M4A -> WAV)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_DECODER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "decodeToWav" -> {
                    val inputBytes = call.argument<ByteArray>("audioBytes")
                    if (inputBytes == null || inputBytes.isEmpty()) {
                        result.error("INVALID_ARGS", "audioBytes cannot be empty", null)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val wavBytes = decodeAudioToWav(inputBytes)
                            runOnUiThread {
                                result.success(wavBytes)
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("DECODE_ERROR", e.message ?: "Failed to decode audio", null)
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingResult?.let {
                it.success(granted)
                pendingResult = null
            }
        }
    }

    private fun decodeAudioToWav(audioBytes: ByteArray): ByteArray {
        val extension = when {
            audioBytes.size >= 2 && (audioBytes[0] == 0xFF.toByte()) && ((audioBytes[1].toInt() and 0xF6) == 0xF0) -> ".aac"
            audioBytes.size >= 3 && audioBytes[0] == 'I'.code.toByte() && audioBytes[1] == 'D'.code.toByte() && audioBytes[2] == '3'.code.toByte() -> ".aac"
            audioBytes.size >= 12 && audioBytes[4] == 'f'.code.toByte() && audioBytes[5] == 't'.code.toByte() && audioBytes[6] == 'y'.code.toByte() && audioBytes[7] == 'p'.code.toByte() -> ".m4a"
            audioBytes.size >= 4 && audioBytes[0] == 'O'.code.toByte() && audioBytes[1] == 'g'.code.toByte() && audioBytes[2] == 'g'.code.toByte() && audioBytes[3] == 'S'.code.toByte() -> ".ogg"
            else -> ".audio"
        }
        val tempInput = File.createTempFile("native_audio_in_", extension, cacheDir)
        try {
            FileOutputStream(tempInput).use { it.write(audioBytes) }

            val extractor = MediaExtractor()
            extractor.setDataSource(tempInput.absolutePath)

            var audioTrackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    inputFormat = format
                    break
                }
            }

            if (audioTrackIndex < 0 || inputFormat == null) {
                throw IllegalArgumentException("В файле не обнаружена аудиодорожка")
            }

            extractor.selectTrack(audioTrackIndex)
            val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
            val decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(inputFormat, null, null, 0)
            decoder.start()

            val pcmOut = ByteArrayOutputStream()
            val bufferInfo = MediaCodec.BufferInfo()
            var sawInputEOS = false
            var sawOutputEOS = false
            var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)

            while (!sawOutputEOS) {
                if (!sawInputEOS) {
                    val inputBufIndex = decoder.dequeueInputBuffer(10000L)
                    if (inputBufIndex >= 0) {
                        val inputBuf = decoder.getInputBuffer(inputBufIndex)!!
                        val sampleSize = extractor.readSampleData(inputBuf, 0)
                        if (sampleSize < 0) {
                            decoder.queueInputBuffer(inputBufIndex, 0, 0, 0L, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            sawInputEOS = true
                        } else {
                            decoder.queueInputBuffer(inputBufIndex, 0, sampleSize, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outputBufIndex = decoder.dequeueOutputBuffer(bufferInfo, 10000L)
                if (outputBufIndex >= 0) {
                    val outputBuf = decoder.getOutputBuffer(outputBufIndex)!!
                    val chunk = ByteArray(bufferInfo.size)
                    outputBuf.get(chunk)
                    outputBuf.clear()
                    if (chunk.isNotEmpty()) {
                        pcmOut.write(chunk)
                    }
                    decoder.releaseOutputBuffer(outputBufIndex, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        sawOutputEOS = true
                    }
                } else if (outputBufIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val newFormat = decoder.outputFormat
                    sampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channelCount = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
            }

            decoder.stop()
            decoder.release()
            extractor.release()

            val rawPcm = pcmOut.toByteArray()
            return buildWavHeader(rawPcm, sampleRate, channelCount)
        } finally {
            try { tempInput.delete() } catch (_: Exception) {}
        }
    }

    private fun buildWavHeader(pcmData: ByteArray, sampleRate: Int, channels: Int): ByteArray {
        val totalAudioLen = pcmData.size.toLong()
        val totalDataLen = totalAudioLen + 36
        val byteRate = (sampleRate * channels * 16 / 8).toLong()

        val header = ByteArray(44)
        val buf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)

        buf.put("RIFF".toByteArray())
        buf.putInt(totalDataLen.toInt())
        buf.put("WAVE".toByteArray())
        buf.put("fmt ".toByteArray())
        buf.putInt(16) // Subchunk1Size for PCM
        buf.putShort(1.toShort()) // AudioFormat 1 = PCM
        buf.putShort(channels.toShort())
        buf.putInt(sampleRate)
        buf.putInt(byteRate.toInt())
        buf.putShort((channels * 16 / 8).toShort()) // BlockAlign
        buf.putShort(16.toShort()) // BitsPerSample
        buf.put("data".toByteArray())
        buf.putInt(totalAudioLen.toInt())

        val wavOut = ByteArrayOutputStream(header.size + pcmData.size)
        wavOut.write(header)
        wavOut.write(pcmData)
        return wavOut.toByteArray()
    }
}
