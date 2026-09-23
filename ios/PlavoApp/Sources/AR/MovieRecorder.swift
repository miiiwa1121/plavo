import AVFoundation

/// ムービーカメラの数秒を書き出す（D58）。
///
/// **ARKit の映像フレームをそのまま動画にする。**カメラは ARKit が握っているので、
/// 別に AVCaptureSession を立てて録ることはできない。毎フレーム届く `capturedImage` を
/// AVAssetWriter に流す。吹き出しは映像の外（SwiftUI）に描いているので動画には入らない（写真と同じ）。
///
/// **音は録らない。**ARKit で音を取るにはマイクの許可が要り、入るのは会場の音だけになる。
///
/// フレームは ARKit のセッションの受け口から**その場で**渡す（`append`）。
/// 画面の仕事（MainActor の Task）へ回してから渡すと、ARFrame を抱えたまま待たせることになり、
/// ARKit が次のフレームを出せなくなる。
final class MovieRecorder: @unchecked Sendable {

    /// 1本の録画。録り始めてから書き終えるまで。
    ///
    /// 書き換えるのは `lock` を持っている間と、書き終えたあとの受け口（`finishWriting`）だけ。
    /// 受け口が走るのは `finishing` を立てたあとで、そのあとはフレームの側から触らない
    private final class Job: @unchecked Sendable {
        let url: URL
        let duration: TimeInterval
        /// 映像の向き。ARKit のフレームは端末の向きによらず横長で来る
        let transform: CGAffineTransform
        let completion: (URL?) -> Void
        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        /// 最初のフレームの時刻。**ここから数えて `duration` 秒で止める**
        var start: TimeInterval?
        var finishing = false

        init(url: URL, duration: TimeInterval, transform: CGAffineTransform, completion: @escaping (URL?) -> Void) {
            self.url = url
            self.duration = duration
            self.transform = transform
            self.completion = completion
        }
    }

    /// フレームは ARKit の受け口から、始める・止めるは画面の仕事から来る。ここで順番を守る
    private let lock = NSLock()
    private var job: Job?

    /// 時刻の刻み。60fps のフレームを取りこぼさない細かさにする
    private static let timescale: CMTimeScale = 60_000

    /// 書き出す先。**起動して最初に使うときに空にする。**写真と同じく永続化しない（D36）ので、
    /// 前に起動したときのファイルはもう誰も指していない
    private static let directory: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Movies", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// 録り始める。`duration` 秒ぶんのフレームが揃ったら書き終えて、ファイルの場所を返す。
    /// 録れなかった（途中で止めた・書き出しに失敗した・すでに録っている）ら nil
    func record(duration: TimeInterval, transform: CGAffineTransform) async -> URL? {
        let url = Self.directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
        return await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            guard job == nil else {
                continuation.resume(returning: nil)
                return
            }
            job = Job(url: url, duration: duration, transform: transform) { continuation.resume(returning: $0) }
        }
    }

    /// 映像のフレームを1枚渡す。録っていなければ何もしない
    func append(_ buffer: CVPixelBuffer, at time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        guard let job, !job.finishing else { return }

        if job.start == nil, !setUp(job, size: (CVPixelBufferGetWidth(buffer), CVPixelBufferGetHeight(buffer)), at: time) {
            fail(job)
            return
        }
        guard let start = job.start else { return }
        let elapsed = time - start
        if elapsed >= job.duration {
            finish(job)
            return
        }
        // 書き出しが追いつかないフレームは捨てる。溜めると ARKit のフレームを抱え続ける
        guard let input = job.input, input.isReadyForMoreMediaData else { return }
        job.adaptor?.append(buffer, withPresentationTime: CMTime(seconds: elapsed, preferredTimescale: Self.timescale))
    }

    /// 録っている途中でやめる（画面を離れた・アプリが背面に回った）。書きかけのファイルは消す
    func cancel() {
        lock.lock()
        guard let job, !job.finishing else {
            lock.unlock()
            return
        }
        self.job = nil
        lock.unlock()
        job.writer?.cancelWriting()
        try? FileManager.default.removeItem(at: job.url)
        job.completion(nil)
    }

    /// 最初のフレームで書き出しの準備をする。**大きさはフレームから決める**（映像の形式で変わる）
    private func setUp(_ job: Job, size: (width: Int, height: Int), at time: TimeInterval) -> Bool {
        guard let writer = try? AVAssetWriter(outputURL: job.url, fileType: .mov) else { return false }
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.hevc,
                AVVideoWidthKey: size.width,
                AVVideoHeightKey: size.height,
            ])
        input.expectsMediaDataInRealTime = true
        input.transform = job.transform
        guard writer.canAdd(input) else { return false }
        writer.add(input)
        // フレームは ARKit の形式（YCbCr）のまま渡す。変換を挟まない
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        job.writer = writer
        job.input = input
        job.adaptor = adaptor
        job.start = time
        return true
    }

    /// 書き終える。**終わりを `duration` ちょうどに揃える。**最後のフレームはそこまで伸びる
    private func finish(_ job: Job) {
        job.finishing = true
        job.input?.markAsFinished()
        job.writer?.endSession(atSourceTime: CMTime(seconds: job.duration, preferredTimescale: Self.timescale))
        job.writer?.finishWriting { [weak self] in
            let completed = job.writer?.status == .completed
            if !completed { try? FileManager.default.removeItem(at: job.url) }
            self?.clear(job)
            job.completion(completed ? job.url : nil)
        }
    }

    private func fail(_ job: Job) {
        self.job = nil
        job.writer?.cancelWriting()
        try? FileManager.default.removeItem(at: job.url)
        job.completion(nil)
    }

    private func clear(_ finished: Job) {
        lock.lock()
        defer { lock.unlock() }
        if job === finished { job = nil }
    }
}
