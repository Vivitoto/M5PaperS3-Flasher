package vink.flasher

import kotlin.math.max

/**
 * Sliding-window flash speed estimator.
 *
 * Each [sample] returns the recent throughput in bytes/second based on the
 * difference between the oldest sample inside [windowMs] and the new sample.
 * Designed to drive the UI speed indicator so the user sees the actual
 * instantaneous flashing rate instead of the running-since-start average.
 *
 * Returns null when fewer than two samples are in the window.
 */
class SpeedWindow(private val windowMs: Long = 1500L) {
    private data class Point(val bytes: Long, val timeMs: Long)

    private val points = ArrayDeque<Point>()

    fun reset() {
        points.clear()
    }

    fun sample(totalBytesWritten: Int, nowMs: Long): Double? {
        // Drop samples older than the window
        val cutoff = nowMs - windowMs
        while (points.isNotEmpty() && points.first().timeMs < cutoff) {
            points.removeFirst()
        }
        points.addLast(Point(totalBytesWritten.toLong(), nowMs))
        if (points.size < 2) return null
        val oldest = points.first()
        val newest = points.last()
        val deltaBytes = newest.bytes - oldest.bytes
        val deltaMs = max(1L, newest.timeMs - oldest.timeMs)
        if (deltaBytes <= 0) return 0.0
        return deltaBytes * 1000.0 / deltaMs
    }
}
