import Foundation

#if canImport(UIKit)
import UIKit

final class CutOverlayView: UIView {
    var cuts: [VideoCut] = [] { didSet { setNeedsLayout() } }
    var duration: TimeInterval = 1 { didSet { setNeedsLayout() } }
    var selectedIndex: Int? { didSet { setNeedsLayout() } }

    var onSelectCut: ((Int) -> Void)?
    var onUpdateSelectedCut: ((VideoCut) -> Void)?

    private let overlayColor = UIColor.systemYellow.withAlphaComponent(0.35)
    private var cutLayers: [CAShapeLayer] = []

    private let leftHandle = UIView()
    private let rightHandle = UIView()
    private var draggingEdge: DraggingEdge?

    private enum DraggingEdge {
        case left
        case right
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true

        [leftHandle, rightHandle].forEach {
            $0.backgroundColor = .systemYellow
            $0.layer.cornerRadius = 3
            addSubview($0)
            $0.isHidden = true
        }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)

        let leftPan = UIPanGestureRecognizer(target: self, action: #selector(handleLeftPan(_:)))
        leftHandle.addGestureRecognizer(leftPan)

        let rightPan = UIPanGestureRecognizer(target: self, action: #selector(handleRightPan(_:)))
        rightHandle.addGestureRecognizer(rightPan)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()

        if cutLayers.count != cuts.count {
            cutLayers.forEach { $0.removeFromSuperlayer() }
            cutLayers = cuts.map { _ in CAShapeLayer() }
            cutLayers.forEach { layer.addSublayer($0) }
        }

        for (idx, cut) in cuts.enumerated() {
            let frame = frame(for: cut)
            let path = UIBezierPath(roundedRect: frame, cornerRadius: 4)
            cutLayers[idx].path = path.cgPath
            cutLayers[idx].fillColor = overlayColor.cgColor
            cutLayers[idx].strokeColor = (idx == selectedIndex ? UIColor.systemYellow : UIColor.clear).cgColor
            cutLayers[idx].lineWidth = 2
        }

        guard let selectedIndex, cuts.indices.contains(selectedIndex) else {
            leftHandle.isHidden = true
            rightHandle.isHidden = true
            return
        }

        let selectedFrame = frame(for: cuts[selectedIndex])
        let handleWidth: CGFloat = 10
        leftHandle.frame = CGRect(x: selectedFrame.minX - handleWidth / 2, y: 0, width: handleWidth, height: bounds.height)
        rightHandle.frame = CGRect(x: selectedFrame.maxX - handleWidth / 2, y: 0, width: handleWidth, height: bounds.height)
        leftHandle.isHidden = false
        rightHandle.isHidden = false
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: self)
        if let idx = cuts.firstIndex(where: { frame(for: $0).contains(point) }) {
            onSelectCut?(idx)
        }
    }

    @objc private func handleLeftPan(_ recognizer: UIPanGestureRecognizer) {
        handlePan(recognizer, edge: .left)
    }

    @objc private func handleRightPan(_ recognizer: UIPanGestureRecognizer) {
        handlePan(recognizer, edge: .right)
    }

    private func handlePan(_ recognizer: UIPanGestureRecognizer, edge: DraggingEdge) {
        guard let selectedIndex, cuts.indices.contains(selectedIndex) else { return }
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)

        if recognizer.state == .began {
            draggingEdge = edge
        }

        guard recognizer.state == .changed, draggingEdge == edge else {
            if recognizer.state == .ended || recognizer.state == .cancelled {
                draggingEdge = nil
            }
            return
        }

        let delta = timeFor(deltaX: translation.x)
        var cut = cuts[selectedIndex]

        switch edge {
        case .left:
            let maxStart = cut.endTime - 0.1
            cut.startTime = max(0, min(maxStart, cut.startTime + delta))
        case .right:
            let minEnd = cut.startTime + 0.1
            cut.endTime = max(minEnd, min(duration, cut.endTime + delta))
        }

        cuts[selectedIndex] = cut
        onUpdateSelectedCut?(cut)
    }

    private func frame(for cut: VideoCut) -> CGRect {
        guard duration > 0 else { return .zero }
        let startX = x(for: cut.startTime)
        let endX = x(for: cut.endTime)
        return CGRect(x: startX, y: 4, width: max(2, endX - startX), height: bounds.height - 8)
    }

    private func x(for time: TimeInterval) -> CGFloat {
        CGFloat(time / duration) * bounds.width
    }

    private func timeFor(deltaX: CGFloat) -> TimeInterval {
        guard bounds.width > 0 else { return 0 }
        return TimeInterval(deltaX / bounds.width) * duration
    }
}
#endif
