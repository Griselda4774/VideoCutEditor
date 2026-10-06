import Foundation

#if canImport(UIKit) && canImport(AVFoundation)
import UIKit
import AVFoundation

public final class VideoTimelineView: UIView, UIScrollViewDelegate {
    public var cuts: [VideoCut] = [] {
        didSet {
            overlayView.cuts = cuts
            setNeedsLayout()
        }
    }

    public var selectedCutIndex: Int? {
        didSet {
            overlayView.selectedIndex = selectedCutIndex
        }
    }

    public var onSeekRequested: ((TimeInterval) -> Void)?
    public var onSelectedCutChanged: ((Int) -> Void)?
    public var onSelectedCutUpdated: ((VideoCut) -> Void)?

    private let asset: AVAsset
    private let duration: TimeInterval
    private let thumbnailProvider: TimelineThumbnailProvider

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let thumbnailsStackView = UIStackView()
    private let overlayView = CutOverlayView()
    private let playheadView = UIView()

    private var zoomScaleValue: CGFloat = 1
    private var thumbnailImageViews: [UIImageView] = []

    public init(asset: AVAsset) {
        self.asset = asset
        self.duration = max(CMTimeGetSeconds(asset.duration), 0.1)
        self.thumbnailProvider = TimelineThumbnailProvider(asset: asset)
        super.init(frame: .zero)
        setupUI()
        configureOverlay()
        loadThumbnails()
    }

    required init?(coder: NSCoder) { nil }

    private func setupUI() {
        backgroundColor = .black

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = true
        addSubview(scrollView)

        scrollView.addSubview(contentView)

        thumbnailsStackView.axis = .horizontal
        thumbnailsStackView.distribution = .fillEqually
        thumbnailsStackView.spacing = 0
        contentView.addSubview(thumbnailsStackView)

        overlayView.backgroundColor = .clear
        contentView.addSubview(overlayView)

        playheadView.backgroundColor = .white
        addSubview(playheadView)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        scrollView.addGestureRecognizer(tap)
    }

    private func configureOverlay() {
        overlayView.duration = duration
        overlayView.onSelectCut = { [weak self] index in
            self?.selectedCutIndex = index
            self?.onSelectedCutChanged?(index)
        }
        overlayView.onUpdateSelectedCut = { [weak self] cut in
            self?.onSelectedCutUpdated?(cut)
            self?.onSeekRequested?(cut.startTime)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()

        scrollView.frame = bounds
        let contentWidth = max(bounds.width * zoomScaleValue, bounds.width)
        contentView.frame = CGRect(x: 0, y: 0, width: contentWidth, height: bounds.height)
        scrollView.contentSize = contentView.bounds.size

        thumbnailsStackView.frame = contentView.bounds
        overlayView.frame = contentView.bounds
        overlayView.duration = duration

        playheadView.frame = CGRect(x: bounds.midX - 1, y: 0, width: 2, height: bounds.height)
    }

    private func loadThumbnails() {
        let count = 24
        let times = (0..<count).map { index in
            (duration / TimeInterval(count)) * TimeInterval(index)
        }

        thumbnailsStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        thumbnailImageViews = (0..<count).map { _ in
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.backgroundColor = .darkGray
            thumbnailsStackView.addArrangedSubview(imageView)
            return imageView
        }

        Task {
            let images = await thumbnailProvider.thumbnails(for: times)
            await MainActor.run {
                for (idx, image) in images.enumerated() where idx < self.thumbnailImageViews.count {
                    self.thumbnailImageViews[idx].image = image
                }
            }
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        if recognizer.state == .changed || recognizer.state == .ended {
            zoomScaleValue = min(5, max(1, zoomScaleValue * recognizer.scale))
            recognizer.scale = 1
            setNeedsLayout()
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: contentView)
        let time = TimeInterval(point.x / max(contentView.bounds.width, 1)) * duration
        onSeekRequested?(time)
    }

    public func updatePlayhead(currentTime: TimeInterval) {
        let x = CGFloat(currentTime / duration) * contentView.bounds.width
        let offsetX = max(0, x - bounds.midX)
        if scrollView.isDragging == false && scrollView.isDecelerating == false {
            scrollView.setContentOffset(CGPoint(x: min(offsetX, max(0, scrollView.contentSize.width - scrollView.bounds.width)), y: 0), animated: false)
        }
    }

    public func scrollToCut(index: Int, animated: Bool) {
        guard cuts.indices.contains(index) else { return }
        let cut = cuts[index]
        let x = CGFloat(cut.startTime / duration) * contentView.bounds.width
        let offsetX = max(0, x - bounds.midX)
        scrollView.setContentOffset(CGPoint(x: min(offsetX, max(0, scrollView.contentSize.width - scrollView.bounds.width)), y: 0), animated: animated)
    }

    public func updateCut(at index: Int, with cut: VideoCut) {
        guard cuts.indices.contains(index) else { return }
        cuts[index] = cut
        overlayView.cuts = cuts
    }
}
#endif
