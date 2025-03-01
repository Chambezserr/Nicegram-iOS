import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramAudio
import UniversalMediaPlayer
import AccountContext
import PhotoResources
import UIKitRuntimeUtils
import RangeSet
import VideoToolbox

private extension CGRect {
    var center: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}

public enum NativeVideoContentId: Hashable {
    case message(UInt32, MediaId)
    case instantPage(MediaId, MediaId)
    case contextResult(Int64, String)
    case profileVideo(Int64, String?)
}

private let isAv1Supported: Bool = {
    let value = VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)
    return value
}()

public final class NativeVideoContent: UniversalVideoContent {
    public let id: AnyHashable
    public let nativeId: NativeVideoContentId
    public let userLocation: MediaResourceUserLocation
    public let fileReference: FileMediaReference
    public let previewSourceFileReference: FileMediaReference?
    public let limitedFileRange: Range<Int64>?
    let imageReference: ImageMediaReference?
    public let dimensions: CGSize
    public let duration: Double
    public let streamVideo: MediaPlayerStreaming
    public let loopVideo: Bool
    public let enableSound: Bool
    public let soundMuted: Bool
    public let beginWithAmbientSound: Bool
    public let mixWithOthers: Bool
    public let baseRate: Double
    public let baseVideoQuality: UniversalVideoContentVideoQuality
    let fetchAutomatically: Bool
    let onlyFullSizeThumbnail: Bool
    let useLargeThumbnail: Bool
    let autoFetchFullSizeThumbnail: Bool
    public let startTimestamp: Double?
    let endTimestamp: Double?
    let continuePlayingWithoutSoundOnLostAudioSession: Bool
    let placeholderColor: UIColor
    let tempFilePath: String?
    let isAudioVideoMessage: Bool
    let captureProtected: Bool
    let hintDimensions: CGSize?
    let storeAfterDownload: (() -> Void)?
    let displayImage: Bool
    let hasSentFramesToDisplay: (() -> Void)?
    
    public static func isVideoCodecSupported(videoCodec: String) -> Bool {
        if videoCodec == "h264" || videoCodec == "h265" || videoCodec == "avc" || videoCodec == "hevc" {
            return true
        }
        
        /*if videoCodec == "av1" {
            if isAv1Supported {
                return true
            }
        }*/
        
        return false
    }
    
    public static func isHLSVideo(file: TelegramMediaFile) -> Bool {
        for alternativeRepresentation in file.alternativeRepresentations {
            if let alternativeFile = alternativeRepresentation as? TelegramMediaFile {
                if alternativeFile.mimeType == "application/x-mpegurl" {
                    return true
                }
            }
        }
        return false
    }
    
    public static func selectVideoQualityFile(file: TelegramMediaFile, quality: UniversalVideoContentVideoQuality) -> TelegramMediaFile {
        guard case let .quality(qualityHeight) = quality else {
            return file
        }
        for alternativeRepresentation in file.alternativeRepresentations {
            if let alternativeFile = alternativeRepresentation as? TelegramMediaFile {
                for attribute in alternativeFile.attributes {
                    if case let .Video(_, size, _, _, _, videoCodec) = attribute {
                        if let videoCodec, isVideoCodecSupported(videoCodec: videoCodec) {
                            if size.height == qualityHeight {
                                return alternativeFile
                            }
                        }
                    }
                }
            }
        }
        return file
    }
    
    public init(id: NativeVideoContentId, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, previewSourceFileReference: FileMediaReference? = nil, limitedFileRange: Range<Int64>? = nil, imageReference: ImageMediaReference? = nil, streamVideo: MediaPlayerStreaming = .none, loopVideo: Bool = false, enableSound: Bool = true, soundMuted: Bool = false, beginWithAmbientSound: Bool = false, mixWithOthers: Bool = false, baseRate: Double = 1.0, baseVideoQuality: UniversalVideoContentVideoQuality = .auto, fetchAutomatically: Bool = true, onlyFullSizeThumbnail: Bool = false, useLargeThumbnail: Bool = false, autoFetchFullSizeThumbnail: Bool = false, startTimestamp: Double? = nil, endTimestamp: Double? = nil, continuePlayingWithoutSoundOnLostAudioSession: Bool = false, placeholderColor: UIColor = .white, tempFilePath: String? = nil, isAudioVideoMessage: Bool = false, captureProtected: Bool = false, hintDimensions: CGSize? = nil, storeAfterDownload: (() -> Void)?, displayImage: Bool = true, hasSentFramesToDisplay: (() -> Void)? = nil) {
        self.id = id
        self.nativeId = id
        self.userLocation = userLocation
        self.fileReference = fileReference
        self.previewSourceFileReference = previewSourceFileReference
        self.limitedFileRange = limitedFileRange
        self.imageReference = imageReference
        if var dimensions = fileReference.media.dimensions {
            if let thumbnail = fileReference.media.previewRepresentations.first {
                let dimensionsVertical = dimensions.width < dimensions.height
                let thumbnailVertical = thumbnail.dimensions.width < thumbnail.dimensions.height
                if dimensionsVertical != thumbnailVertical {
                    dimensions = PixelDimensions(width: dimensions.height, height: dimensions.width)
                }
            }
            self.dimensions = dimensions.cgSize
        } else {
            self.dimensions = CGSize(width: 128.0, height: 128.0)
        }
        
        self.duration = fileReference.media.duration ?? 0.0
        self.streamVideo = streamVideo
        self.loopVideo = loopVideo
        self.enableSound = enableSound
        self.soundMuted = soundMuted
        self.beginWithAmbientSound = beginWithAmbientSound
        self.mixWithOthers = mixWithOthers
        self.baseRate = baseRate
        self.baseVideoQuality = baseVideoQuality
        self.fetchAutomatically = fetchAutomatically
        self.onlyFullSizeThumbnail = onlyFullSizeThumbnail
        self.useLargeThumbnail = useLargeThumbnail
        self.autoFetchFullSizeThumbnail = autoFetchFullSizeThumbnail
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.continuePlayingWithoutSoundOnLostAudioSession = continuePlayingWithoutSoundOnLostAudioSession
        self.placeholderColor = placeholderColor
        self.tempFilePath = tempFilePath
        self.captureProtected = captureProtected
        self.isAudioVideoMessage = isAudioVideoMessage
        self.hintDimensions = hintDimensions
        self.storeAfterDownload = storeAfterDownload
        self.displayImage = displayImage
        self.hasSentFramesToDisplay = hasSentFramesToDisplay
    }
    
    public func makeContentNode(accountId: AccountRecordId, postbox: Postbox, audioSession: ManagedAudioSession) -> UniversalVideoContentNode & ASDisplayNode {
        return NativeVideoContentNode(postbox: postbox, audioSessionManager: audioSession, userLocation: self.userLocation, fileReference: self.fileReference, previewSourceFileReference: self.previewSourceFileReference, limitedFileRange: self.limitedFileRange, imageReference: self.imageReference, streamVideo: self.streamVideo, loopVideo: self.loopVideo, enableSound: self.enableSound, soundMuted: self.soundMuted, beginWithAmbientSound: self.beginWithAmbientSound, mixWithOthers: self.mixWithOthers, baseRate: self.baseRate, baseVideoQuality: self.baseVideoQuality, fetchAutomatically: self.fetchAutomatically, onlyFullSizeThumbnail: self.onlyFullSizeThumbnail, useLargeThumbnail: self.useLargeThumbnail, autoFetchFullSizeThumbnail: self.autoFetchFullSizeThumbnail, startTimestamp: self.startTimestamp, endTimestamp: self.endTimestamp, continuePlayingWithoutSoundOnLostAudioSession: self.continuePlayingWithoutSoundOnLostAudioSession, placeholderColor: self.placeholderColor, tempFilePath: self.tempFilePath, isAudioVideoMessage: self.isAudioVideoMessage, captureProtected: self.captureProtected, hintDimensions: self.hintDimensions, storeAfterDownload: self.storeAfterDownload, displayImage: self.displayImage, hasSentFramesToDisplay: self.hasSentFramesToDisplay)
    }
    
    public func isEqual(to other: UniversalVideoContent) -> Bool {
        if let other = other as? NativeVideoContent {
            if case let .message(stableId, _) = self.nativeId {
                if case .message(stableId, _) = other.nativeId {
                    if self.fileReference.media.isInstantVideo {
                        return true
                    }
                }
            }
        }
        return false
    }
}

private final class NativeVideoContentNode: ASDisplayNode, UniversalVideoContentNode {
    private let postbox: Postbox
    private let userLocation: MediaResourceUserLocation
    private let fileReference: FileMediaReference
    private let previewSourceFileReference: FileMediaReference?
    private let limitedFileRange: Range<Int64>?
    private let streamVideo: MediaPlayerStreaming
    private let enableSound: Bool
    private let soundMuted: Bool
    private let beginWithAmbientSound: Bool
    private let mixWithOthers: Bool
    private let loopVideo: Bool
    private let baseRate: Double
    private var baseVideoQuality: UniversalVideoContentVideoQuality
    private let audioSessionManager: ManagedAudioSession
    private let isAudioVideoMessage: Bool
    private let captureProtected: Bool
    private let continuePlayingWithoutSoundOnLostAudioSession: Bool
    private let displayImage: Bool
    
    private var player: MediaPlayer
    private var thumbnailPlayer: MediaPlayer?
    private let imageNode: TransformImageNode
    private let playerNode: MediaPlayerNode
    private var thumbnailNode: MediaPlayerNode?
    private let playbackCompletedListeners = Bag<() -> Void>()
    
    private let placeholderColor: UIColor
    
    private var initializedStatus = false
    private let _status = Promise<MediaPlayerStatus>()
    private let _thumbnailStatus = Promise<MediaPlayerStatus?>(nil)
    var status: Signal<MediaPlayerStatus, NoError> {
        return combineLatest(self._thumbnailStatus.get(), self._status.get())
        |> map { thumbnailStatus, status in
            switch status.status {
            case .buffering:
                if let thumbnailStatus = thumbnailStatus {
                    return thumbnailStatus
                } else {
                    return status
                }
            default:
                return status
            }
        }
    }
    
    private let _bufferingStatus = Promise<(RangeSet<Int64>, Int64)?>()
    var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> {
        return self._bufferingStatus.get()
    }
    
    var isNativePictureInPictureActive: Signal<Bool, NoError> {
        return .single(false)
    }
    
    private let _ready = Promise<Void>()
    var ready: Signal<Void, NoError> {
        return self._ready.get()
    }
    
    private let fetchDisposable = MetaDisposable()
    private let fetchStatusDisposable = MetaDisposable()
    
    private var dimensions: CGSize?
    private let dimensionsPromise = ValuePromise<CGSize>(CGSize())
    
    private var validLayout: (size: CGSize, actualSize: CGSize)?
    
    private var shouldPlay: Bool = false
    
    private let hasSentFramesToDisplay: (() -> Void)?
    
    init(postbox: Postbox, audioSessionManager: ManagedAudioSession, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, previewSourceFileReference: FileMediaReference?, limitedFileRange: Range<Int64>?, imageReference: ImageMediaReference?, streamVideo: MediaPlayerStreaming, loopVideo: Bool, enableSound: Bool, soundMuted: Bool, beginWithAmbientSound: Bool, mixWithOthers: Bool, baseRate: Double, baseVideoQuality: UniversalVideoContentVideoQuality, fetchAutomatically: Bool, onlyFullSizeThumbnail: Bool, useLargeThumbnail: Bool, autoFetchFullSizeThumbnail: Bool, startTimestamp: Double?, endTimestamp: Double?, continuePlayingWithoutSoundOnLostAudioSession: Bool = false, placeholderColor: UIColor, tempFilePath: String?, isAudioVideoMessage: Bool, captureProtected: Bool, hintDimensions: CGSize?, storeAfterDownload: (() -> Void)? = nil, displayImage: Bool, hasSentFramesToDisplay: (() -> Void)?) {
        self.postbox = postbox
        self.userLocation = userLocation
        self.fileReference = fileReference
        self.previewSourceFileReference = previewSourceFileReference
        self.limitedFileRange = limitedFileRange
        self.streamVideo = streamVideo
        self.placeholderColor = placeholderColor
        self.enableSound = enableSound
        self.soundMuted = soundMuted
        self.beginWithAmbientSound = beginWithAmbientSound
        self.mixWithOthers = mixWithOthers
        self.loopVideo = loopVideo
        self.baseRate = baseRate
        self.baseVideoQuality = baseVideoQuality
        self.audioSessionManager = audioSessionManager
        self.isAudioVideoMessage = isAudioVideoMessage
        self.captureProtected = captureProtected
        self.continuePlayingWithoutSoundOnLostAudioSession = continuePlayingWithoutSoundOnLostAudioSession
        self.displayImage = displayImage
        self.hasSentFramesToDisplay = hasSentFramesToDisplay
        
        self.imageNode = TransformImageNode()
        
        var userContentType = MediaResourceUserContentType(file: fileReference.media)
        switch fileReference {
        case .story:
            userContentType = .story
        default:
            break
        }
        
        let selectedFile = NativeVideoContent.selectVideoQualityFile(file: fileReference.media, quality: self.baseVideoQuality)
        
        self.player = MediaPlayer(audioSessionManager: audioSessionManager, postbox: postbox, userLocation: userLocation, userContentType: userContentType, resourceReference: fileReference.resourceReference(selectedFile.resource), tempFilePath: tempFilePath, limitedFileRange: limitedFileRange, streamable: streamVideo, video: true, preferSoftwareDecoding: false, playAutomatically: false, enableSound: enableSound, baseRate: baseRate, fetchAutomatically: fetchAutomatically, soundMuted: soundMuted, ambient: beginWithAmbientSound, mixWithOthers: mixWithOthers, continuePlayingWithoutSoundOnLostAudioSession: continuePlayingWithoutSoundOnLostAudioSession, storeAfterDownload: storeAfterDownload, isAudioVideoMessage: isAudioVideoMessage)
        
        var actionAtEndImpl: (() -> Void)?
        if enableSound && !loopVideo {
            self.player.actionAtEnd = .action({
                actionAtEndImpl?()
            })
        } else {
            self.player.actionAtEnd = .loop({
                actionAtEndImpl?()
            })
        }
        self.playerNode = MediaPlayerNode(backgroundThread: false, captureProtected: captureProtected)
        self.player.attachPlayerNode(self.playerNode)
        
        self.dimensions = fileReference.media.dimensions?.cgSize
        if let dimensions = self.dimensions {
            self.dimensionsPromise.set(dimensions)
        }
        
        super.init()
        
        var didProcessFramesToDisplay = false
        self.playerNode.hasSentFramesToDisplay = { [weak self] in
            guard let self, !didProcessFramesToDisplay else {
                return
            }
            didProcessFramesToDisplay = true
            self.hasSentFramesToDisplay?()
        }
        
        if let dimensions = hintDimensions {
            self.dimensions = dimensions
            self.dimensionsPromise.set(dimensions)
        }
        
        actionAtEndImpl = { [weak self] in
            self?.performActionAtEnd()
        }
        
        if displayImage {
            if captureProtected {
                setLayerDisableScreenshots(self.imageNode.layer, captureProtected)
            }
            
            self.imageNode.setSignal(internalMediaGridMessageVideo(postbox: postbox, userLocation: userLocation, videoReference: fileReference, previewSourceFileReference: previewSourceFileReference, imageReference: imageReference, onlyFullSize: onlyFullSizeThumbnail, useLargeThumbnail: useLargeThumbnail, autoFetchFullSizeThumbnail: autoFetchFullSizeThumbnail || fileReference.media.isInstantVideo) |> map { [weak self] getSize, getData in
                Queue.mainQueue().async {
                    if let strongSelf = self, strongSelf.dimensions == nil {
                        if let dimensions = getSize() {
                            strongSelf.dimensions = dimensions
                            strongSelf.dimensionsPromise.set(dimensions)
                            if let validLayout = strongSelf.validLayout {
                                strongSelf.updateLayout(size: validLayout.size, actualSize: validLayout.actualSize, transition: .immediate)
                            }
                        }
                    }
                }
                return getData
            })
            
            self.addSubnode(self.imageNode)
        }
        
        self.addSubnode(self.playerNode)
        self._status.set(combineLatest(self.dimensionsPromise.get(), self.player.status)
        |> map { dimensions, status in
            return MediaPlayerStatus(generationTimestamp: status.generationTimestamp, duration: status.duration, dimensions: dimensions, timestamp: status.timestamp, baseRate: status.baseRate, seekId: status.seekId, status: status.status, soundEnabled: status.soundEnabled)
        })
        
        self.fetchStatusDisposable.set((postbox.mediaBox.resourceStatus(selectedFile.resource)
        |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let strongSelf = self else {
                return
            }
            switch status {
            case .Local:
                break
            default:
                if strongSelf.thumbnailPlayer == nil {
                    strongSelf.createThumbnailPlayer()
                }
            }
        }))
        
        if let size = selectedFile.size {
            self._bufferingStatus.set(postbox.mediaBox.resourceRangesStatus(selectedFile.resource) |> map { ranges in
                return (ranges, size)
            })
        } else {
            self._bufferingStatus.set(.single(nil))
        }
        
        if self.displayImage {
            self.imageNode.imageUpdated = { [weak self] _ in
                self?._ready.set(.single(Void()))
            }
        } else {
            self._ready.set(.single(Void()))
        }
        
        if let startTimestamp = startTimestamp {
            self.seek(startTimestamp)
        }
    }
    
    deinit {
        self.player.pause()
        self.thumbnailPlayer?.pause()
        self.fetchDisposable.dispose()
        self.fetchStatusDisposable.dispose()
    }
    
    private func createThumbnailPlayer() {
        guard let videoThumbnail = self.fileReference.media.videoThumbnails.first else {
            return
        }
        
        let thumbnailPlayer = MediaPlayer(audioSessionManager: self.audioSessionManager, postbox: postbox, userLocation: self.userLocation, userContentType: MediaResourceUserContentType(file: self.fileReference.media), resourceReference: self.fileReference.resourceReference(videoThumbnail.resource), tempFilePath: nil, streamable: .none, video: true, preferSoftwareDecoding: false, playAutomatically: false, enableSound: false, baseRate: self.baseRate, fetchAutomatically: false, continuePlayingWithoutSoundOnLostAudioSession: false)
        self.thumbnailPlayer = thumbnailPlayer
        
        var actionAtEndImpl: (() -> Void)?
        if self.enableSound && !self.loopVideo {
            thumbnailPlayer.actionAtEnd = .action({
                actionAtEndImpl?()
            })
        } else {
            thumbnailPlayer.actionAtEnd = .loop({
                actionAtEndImpl?()
            })
        }
        
        actionAtEndImpl = { [weak self] in
            self?.performActionAtEnd()
        }
        
        let thumbnailNode = MediaPlayerNode(backgroundThread: false)
        self.thumbnailNode = thumbnailNode
        thumbnailPlayer.attachPlayerNode(thumbnailNode)
        
        self._thumbnailStatus.set(thumbnailPlayer.status
        |> map { status in
            return MediaPlayerStatus(generationTimestamp: status.generationTimestamp, duration: status.duration, dimensions: CGSize(), timestamp: status.timestamp, baseRate: status.baseRate, seekId: status.seekId, status: status.status, soundEnabled: status.soundEnabled)
        })
        
        self.addSubnode(thumbnailNode)
        
        thumbnailNode.frame = self.playerNode.frame
        
        if self.shouldPlay {
            thumbnailPlayer.play()
        }
        
        var processedSentFramesToDisplay = false
        self.playerNode.hasSentFramesToDisplay = { [weak self] in
            guard !processedSentFramesToDisplay, let strongSelf = self else {
                return
            }
            processedSentFramesToDisplay = true
            
            strongSelf.hasSentFramesToDisplay?()
            
            Queue.mainQueue().after(0.1, {
                guard let strongSelf = self else {
                    return
                }
                strongSelf.thumbnailNode?.isHidden = true
                strongSelf.thumbnailPlayer?.pause()
            })
        }
    }
    
    private func performActionAtEnd() {
        for listener in self.playbackCompletedListeners.copyItems() {
            listener()
        }
    }
    
    func updateLayout(size: CGSize, actualSize: CGSize, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, actualSize)
        
        if let dimensions = self.dimensions {
            let imageSize = CGSize(width: floor(dimensions.width / 2.0), height: floor(dimensions.height / 2.0))
            let makeLayout = self.imageNode.asyncLayout()
            let applyLayout = makeLayout(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: UIEdgeInsets(), emptyColor: self.fileReference.media.isInstantVideo ? .clear : self.placeholderColor))
            applyLayout()
        }
        
        transition.updateFrame(node: self.imageNode, frame: CGRect(origin: CGPoint(), size: size))
        let fromFrame = self.playerNode.frame
        let toFrame = CGRect(origin: CGPoint(), size: size).insetBy(dx: -1.0, dy: -1.0)
        if case let .animated(duration, curve) = transition, fromFrame != toFrame, !fromFrame.width.isZero, !fromFrame.height.isZero, !toFrame.width.isZero, !toFrame.height.isZero {
            self.playerNode.frame = toFrame
            transition.animatePosition(node: self.playerNode, from: CGPoint(x: fromFrame.center.x - toFrame.center.x, y: fromFrame.center.y - toFrame.center.y))
            
            let transform = CATransform3DScale(CATransform3DIdentity, fromFrame.width / toFrame.width, fromFrame.height / toFrame.height, 1.0)
            self.playerNode.layer.animate(from: NSValue(caTransform3D: transform), to: NSValue(caTransform3D: CATransform3DIdentity), keyPath: "transform", timingFunction: curve.timingFunction, duration: duration)
        } else {
            transition.updateFrame(node: self.playerNode, frame: toFrame)
        }
        if let thumbnailNode = self.thumbnailNode {
            transition.updateFrame(node: thumbnailNode, frame: CGRect(origin: CGPoint(), size: size).insetBy(dx: -1.0, dy: -1.0))
        }
    }
    
    func play() {
        assert(Queue.mainQueue().isCurrent())
        self.player.play()
        self.shouldPlay = true
        self.thumbnailPlayer?.play()
    }
    
    func pause() {
        assert(Queue.mainQueue().isCurrent())
        self.player.pause()
        self.shouldPlay = false
        self.thumbnailPlayer?.pause()
    }
    
    func togglePlayPause() {
        assert(Queue.mainQueue().isCurrent())
        self.player.togglePlayPause()
        self.shouldPlay = !self.shouldPlay
        self.thumbnailPlayer?.togglePlayPause()
    }
    
    func setSoundEnabled(_ value: Bool) {
        assert(Queue.mainQueue().isCurrent())
        if value {
            self.player.playOnceWithSound(playAndRecord: false, seek: .none)
        } else {
            self.player.continuePlayingWithoutSound(seek: .none)
        }
    }
    
    func seek(_ timestamp: Double) {
        assert(Queue.mainQueue().isCurrent())
        self.player.seek(timestamp: timestamp)
    }
    
    func playOnceWithSound(playAndRecord: Bool, seek: MediaPlayerSeek, actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd) {
        assert(Queue.mainQueue().isCurrent())
        let action = { [weak self] in
            Queue.mainQueue().async {
                self?.performActionAtEnd()
            }
        }
        switch actionAtEnd {
            case .loop:
                self.player.actionAtEnd = .loop({})
            case .loopDisablingSound:
                self.player.actionAtEnd = .loopDisablingSound(action)
            case .stop:
                self.player.actionAtEnd = .action(action)
            case .repeatIfNeeded:
                let _ = (self.player.status
                |> deliverOnMainQueue
                |> take(1)).start(next: { [weak self] status in
                    guard let strongSelf = self else {
                        return
                    }
                    if status.timestamp > status.duration * 0.1 {
                        strongSelf.player.actionAtEnd = .loop({ [weak self] in
                            guard let strongSelf = self else {
                                return
                            }
                            strongSelf.player.actionAtEnd = .loopDisablingSound(action)
                        })
                    } else {
                        strongSelf.player.actionAtEnd = .loopDisablingSound(action)
                    }
                })
        }
        
        self.player.playOnceWithSound(playAndRecord: playAndRecord, seek: seek)
    }
    
    func setForceAudioToSpeaker(_ forceAudioToSpeaker: Bool) {
        assert(Queue.mainQueue().isCurrent())
        self.player.setForceAudioToSpeaker(forceAudioToSpeaker)
    }
    
    func setSoundMuted(soundMuted: Bool) {
        self.player.setSoundMuted(soundMuted: soundMuted)
    }
    
    func continueWithOverridingAmbientMode(isAmbient: Bool) {
        self.player.continueWithOverridingAmbientMode(isAmbient: isAmbient)
    }
    
    func setBaseRate(_ baseRate: Double) {
        self.player.setBaseRate(baseRate)
    }
    
    func setVideoQuality(_ quality: UniversalVideoContentVideoQuality) {
        let _ = (self._status.get()
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { [weak self] status in
            guard let self else {
                return
            }
            
            if self.baseVideoQuality == quality {
                return
            }
            self.baseVideoQuality = quality
            
            let selectedFile = NativeVideoContent.selectVideoQualityFile(file: self.fileReference.media, quality: self.baseVideoQuality)
            
            let updatedFileReference: FileMediaReference = self.fileReference.withMedia(selectedFile)
            
            var userContentType = MediaResourceUserContentType(file: selectedFile)
            switch updatedFileReference {
            case .story:
                userContentType = .story
            default:
                break
            }
            
            self._status.set(.never())
            self.player.pause()
            
            self.player = MediaPlayer(audioSessionManager: self.audioSessionManager, postbox: self.postbox, userLocation: self.userLocation, userContentType: userContentType, resourceReference: updatedFileReference.resourceReference(selectedFile.resource), tempFilePath: nil, streamable: self.streamVideo, video: true, preferSoftwareDecoding: false, playAutomatically: false, enableSound: self.enableSound, baseRate: self.baseRate, fetchAutomatically: true, soundMuted: self.soundMuted, ambient: beginWithAmbientSound, mixWithOthers: mixWithOthers, continuePlayingWithoutSoundOnLostAudioSession: self.continuePlayingWithoutSoundOnLostAudioSession, storeAfterDownload: nil, isAudioVideoMessage: self.isAudioVideoMessage)
            
            var actionAtEndImpl: (() -> Void)?
            if self.enableSound && !self.loopVideo {
                self.player.actionAtEnd = .action({
                    actionAtEndImpl?()
                })
            } else {
                self.player.actionAtEnd = .loop({
                    actionAtEndImpl?()
                })
            }
            actionAtEndImpl = { [weak self] in
                self?.performActionAtEnd()
            }
            
            self._status.set(combineLatest(self.dimensionsPromise.get(), self.player.status)
            |> map { dimensions, status in
                return MediaPlayerStatus(generationTimestamp: status.generationTimestamp, duration: status.duration, dimensions: dimensions, timestamp: status.timestamp, baseRate: status.baseRate, seekId: status.seekId, status: status.status, soundEnabled: status.soundEnabled)
            })
            
            self.fetchStatusDisposable.set((self.postbox.mediaBox.resourceStatus(selectedFile.resource)
            |> deliverOnMainQueue).start(next: { [weak self] status in
                guard let strongSelf = self else {
                    return
                }
                switch status {
                case .Local:
                    break
                default:
                    if strongSelf.thumbnailPlayer == nil {
                        strongSelf.createThumbnailPlayer()
                    }
                }
            }))
            
            if let size = updatedFileReference.media.size {
                self._bufferingStatus.set(postbox.mediaBox.resourceRangesStatus(selectedFile.resource) |> map { ranges in
                    return (ranges, size)
                })
            } else {
                self._bufferingStatus.set(.single(nil))
            }
            
            self.player.attachPlayerNode(self.playerNode)
            
            var play = false
            switch status.status {
            case .playing:
                play = true
            case let .buffering(_, whilePlaying, _, _):
                play = whilePlaying
            case .paused:
                break
            }
            self.player.seek(timestamp: status.timestamp, play: play)
        })
    }
    
    func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])? {
        return nil
    }
    
    func videoQualityStateSignal() -> Signal<(current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])?, NoError> {
        return .single(nil)
    }
    
    func continuePlayingWithoutSound(actionAtEnd: MediaPlayerPlayOnceWithSoundActionAtEnd) {
        assert(Queue.mainQueue().isCurrent())
        let action = { [weak self] in
            Queue.mainQueue().async {
                self?.performActionAtEnd()
            }
        }
        switch actionAtEnd {
            case .loop:
                self.player.actionAtEnd = .loop({})
            case .loopDisablingSound, .repeatIfNeeded:
                self.player.actionAtEnd = .loopDisablingSound(action)
            case .stop:
                self.player.actionAtEnd = .action(action)
        }
        self.player.continuePlayingWithoutSound()
    }
    
    func setContinuePlayingWithoutSoundOnLostAudioSession(_ value: Bool) {
        self.player.setContinuePlayingWithoutSoundOnLostAudioSession(value)
    }
    
    func addPlaybackCompleted(_ f: @escaping () -> Void) -> Int {
        return self.playbackCompletedListeners.add(f)
    }
    
    func removePlaybackCompleted(_ index: Int) {
        self.playbackCompletedListeners.remove(index)
    }
    
    func fetchControl(_ control: UniversalVideoNodeFetchControl) {
        switch control {
            case .fetch:
            self.fetchDisposable.set(fetchedMediaResource(mediaBox: self.postbox.mediaBox, userLocation: self.userLocation, userContentType: .video, reference: self.fileReference.resourceReference(self.fileReference.media.resource), statsCategory: statsCategoryForFileWithAttributes(self.fileReference.media.attributes)).start())
            case .cancel:
                self.postbox.mediaBox.cancelInteractiveResourceFetch(self.fileReference.media.resource)
        }
    }
    
    func notifyPlaybackControlsHidden(_ hidden: Bool) {
    }

    func setCanPlaybackWithoutHierarchy(_ canPlaybackWithoutHierarchy: Bool) {
        self.playerNode.setCanPlaybackWithoutHierarchy(canPlaybackWithoutHierarchy)
    }
    
    func enterNativePictureInPicture() -> Bool {
        return false
    }
    
    func exitNativePictureInPicture() {
    }
    
    func setNativePictureInPictureIsActive(_ value: Bool) {
        self.imageNode.isHidden = value
    }
}
