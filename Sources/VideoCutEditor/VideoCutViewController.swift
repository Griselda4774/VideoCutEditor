import Foundation

#if canImport(UIKit) && canImport(AVFoundation)
import UIKit
import AVFoundation

public final class VideoCutViewController: UIViewController {
    public var onExportCompleted: ((URL) -> Void)?

    private let videoURL: URL
    private let asset: AVURLAsset
    private var cuts: [VideoCut]
    private var selectedCutIndex: Int?

    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    private var timeObserver: Any?
    private var previewSegmentEndTime: TimeInterval?
    private var isPreviewingFinal = false

    private let exporter = VideoCutExporter()

    private let playPauseButton = UIButton(type: .system)
    private let timeLabel = UILabel()
    private let timelineContainer = UIView()
    private var timelineView: VideoTimelineView?
    private let addCutButton = UIButton(type: .system)
    private let previewSegmentButton = UIButton(type: .system)
    private let previewFinalButton = UIButton(type: .system)
    private let deleteCutButton = UIButton(type: .system)

    private let startTextField = UITextField()
    private let endTextField = UITextField()

    private let cutsTableView = UITableView(frame: .zero, style: .insetGrouped)
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let cancelExportButton = UIButton(type: .system)

    public init(videoURL: URL, cuts: [VideoCut]) {
        self.videoURL = videoURL
        self.asset = AVURLAsset(url: videoURL)
        self.cuts = cuts
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    public override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configurePlayer()
        configureTimeline()
        normalizeCutsAndReload(select: 0)
    }

    deinit {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
        }
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        playerLayer.frame = CGRect(x: 0, y: view.safeAreaInsets.top + 44, width: view.bounds.width, height: 220)
    }

    private func setupUI() {
        view.backgroundColor = .black

        navigationItem.title = "Cut Highlights"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))

        playerLayer.videoGravity = .resizeAspect
        view.layer.addSublayer(playerLayer)

        playPauseButton.setTitle("Play", for: .normal)
        playPauseButton.tintColor = .systemYellow
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)

        timeLabel.textColor = .white
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let controlsStack = UIStackView(arrangedSubviews: [playPauseButton, UIView(), timeLabel])
        controlsStack.axis = .horizontal
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controlsStack)

        timelineContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timelineContainer)

        addCutButton.setTitle("Add Cut", for: .normal)
        previewSegmentButton.setTitle("Preview Segment", for: .normal)
        previewFinalButton.setTitle("Preview Final", for: .normal)
        deleteCutButton.setTitle("Delete Cut", for: .normal)
        [addCutButton, previewSegmentButton, previewFinalButton, deleteCutButton].forEach {
            $0.tintColor = .systemYellow
            $0.layer.borderColor = UIColor.systemYellow.cgColor
            $0.layer.borderWidth = 1
            $0.layer.cornerRadius = 8
            $0.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
            $0.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let buttonStack = UIStackView(arrangedSubviews: [addCutButton, previewSegmentButton, previewFinalButton, deleteCutButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 8
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonStack)

        startTextField.placeholder = "Start (mm:ss)"
        endTextField.placeholder = "End (mm:ss)"
        [startTextField, endTextField].forEach {
            $0.backgroundColor = UIColor(white: 0.15, alpha: 1)
            $0.textColor = .white
            $0.keyboardType = .numbersAndPunctuation
            $0.autocapitalizationType = .none
            $0.autocorrectionType = .no
            $0.borderStyle = .roundedRect
            $0.addTarget(self, action: #selector(timeFieldEditingDidEnd(_:)), for: .editingDidEnd)
            $0.heightAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let timeFields = UIStackView(arrangedSubviews: [startTextField, endTextField])
        timeFields.axis = .horizontal
        timeFields.spacing = 8
        timeFields.distribution = .fillEqually
        timeFields.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timeFields)

        cutsTableView.dataSource = self
        cutsTableView.delegate = self
        cutsTableView.backgroundColor = .clear
        cutsTableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cutsTableView)

        progressView.progress = 0
        progressView.trackTintColor = UIColor(white: 0.2, alpha: 1)
        progressView.progressTintColor = .systemYellow
        progressView.isHidden = true
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)

        cancelExportButton.setTitle("Cancel Export", for: .normal)
        cancelExportButton.tintColor = .systemYellow
        cancelExportButton.addTarget(self, action: #selector(cancelExportTapped), for: .touchUpInside)
        cancelExportButton.isHidden = true
        cancelExportButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelExportButton)

        NSLayoutConstraint.activate([
            controlsStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 228),
            controlsStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controlsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            timelineContainer.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 12),
            timelineContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            timelineContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            timelineContainer.heightAnchor.constraint(equalToConstant: 92),

            buttonStack.topAnchor.constraint(equalTo: timelineContainer.bottomAnchor, constant: 12),
            buttonStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            timeFields.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: 12),
            timeFields.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            timeFields.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            cutsTableView.topAnchor.constraint(equalTo: timeFields.bottomAnchor, constant: 8),
            cutsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cutsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cutsTableView.bottomAnchor.constraint(equalTo: progressView.topAnchor, constant: -8),

            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            progressView.bottomAnchor.constraint(equalTo: cancelExportButton.topAnchor, constant: -8),

            cancelExportButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            cancelExportButton.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func configurePlayer() {
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        playerLayer.player = player

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            self?.refreshTimeLabel()
            self?.syncPreviewLimits()
            self?.timelineView?.updatePlayhead(currentTime: self?.currentTime ?? 0)
        }

        refreshTimeLabel()
    }

    private func configureTimeline() {
        let timeline = VideoTimelineView(asset: asset)
        timeline.translatesAutoresizingMaskIntoConstraints = false
        timeline.cuts = cuts
        timeline.onSeekRequested = { [weak self] time in
            self?.seek(to: time)
        }
        timeline.onSelectedCutChanged = { [weak self] index in
            self?.selectedCutIndex = index
            self?.refreshCutEditors()
            self?.cutsTableView.reloadData()
        }
        timeline.onSelectedCutUpdated = { [weak self] cut in
            guard let self, let selectedCutIndex else { return }
            self.cuts[selectedCutIndex] = cut
            self.refreshCutEditors()
            self.cutsTableView.reloadData()
        }

        timelineContainer.addSubview(timeline)
        NSLayoutConstraint.activate([
            timeline.topAnchor.constraint(equalTo: timelineContainer.topAnchor),
            timeline.leadingAnchor.constraint(equalTo: timelineContainer.leadingAnchor),
            timeline.trailingAnchor.constraint(equalTo: timelineContainer.trailingAnchor),
            timeline.bottomAnchor.constraint(equalTo: timelineContainer.bottomAnchor)
        ])
        timelineView = timeline
    }

    @objc private func playPauseTapped() {
        if player.timeControlStatus == .playing {
            player.pause()
            playPauseButton.setTitle("Play", for: .normal)
        } else {
            player.play()
            playPauseButton.setTitle("Pause", for: .normal)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        switch sender {
        case addCutButton:
            addCut()
        case previewSegmentButton:
            previewSelectedSegment()
        case previewFinalButton:
            previewFinalVideo()
        case deleteCutButton:
            deleteSelectedCut()
        default:
            break
        }
    }

    @objc private func timeFieldEditingDidEnd(_ sender: UITextField) {
        guard let selectedCutIndex, cuts.indices.contains(selectedCutIndex) else { return }
        guard let text = sender.text, let value = parseShortTime(text) else { return }

        let duration = CMTimeGetSeconds(asset.duration)
        var cut = cuts[selectedCutIndex]

        if sender === startTextField {
            cut.startTime = max(0, min(cut.endTime - 0.1, value))
        } else {
            cut.endTime = min(duration, max(cut.startTime + 0.1, value))
        }

        cuts[selectedCutIndex] = cut
        normalizeCutsAndReload(select: selectedCutIndex)
        seek(to: sender === startTextField ? cut.startTime : cut.endTime)
    }

    @objc private func doneTapped() {
        let duration = CMTimeGetSeconds(asset.duration)
        cuts = VideoCutValidator.normalizedCuts(cuts, duration: duration)
        timelineView?.cuts = cuts
        cutsTableView.reloadData()

        let outputURL: URL
        do {
            outputURL = try VideoCutFileManager.makeOutputURL()
            VideoCutFileManager.remove(outputURL)
        } catch {
            presentAlert(title: "Export Error", message: error.localizedDescription)
            return
        }

        progressView.isHidden = false
        cancelExportButton.isHidden = false
        navigationItem.rightBarButtonItem?.isEnabled = false

        exporter.export(sourceURL: videoURL, cuts: cuts, outputURL: outputURL, progress: { [weak self] value in
            DispatchQueue.main.async {
                self?.progressView.progress = value
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            self.progressView.isHidden = true
            self.cancelExportButton.isHidden = true
            self.navigationItem.rightBarButtonItem?.isEnabled = true

            switch result {
            case .success(let url):
                self.onExportCompleted?(url)
                self.dismiss(animated: true)
            case .failure(let error):
                self.presentAlert(title: "Export Error", message: error.localizedDescription)
            }
        })
    }

    @objc private func cancelExportTapped() {
        exporter.cancel()
        progressView.isHidden = true
        cancelExportButton.isHidden = true
        navigationItem.rightBarButtonItem?.isEnabled = true
    }

    private func addCut() {
        let current = currentTime
        let duration = CMTimeGetSeconds(asset.duration)
        let end = min(duration, current + 5)
        guard end > current else { return }
        cuts.append(VideoCut(startTime: current, endTime: end))
        normalizeCutsAndReload(select: cuts.count - 1)
    }

    private func deleteSelectedCut() {
        guard let selectedCutIndex, cuts.indices.contains(selectedCutIndex) else { return }
        cuts.remove(at: selectedCutIndex)
        normalizeCutsAndReload(select: min(selectedCutIndex, cuts.count - 1))
    }

    private func normalizeCutsAndReload(select index: Int?) {
        let duration = CMTimeGetSeconds(asset.duration)
        cuts = VideoCutValidator.normalizedCuts(cuts, duration: duration)
        timelineView?.cuts = cuts

        if let index, cuts.indices.contains(index) {
            selectedCutIndex = index
        } else {
            selectedCutIndex = cuts.isEmpty ? nil : 0
        }

        timelineView?.selectedCutIndex = selectedCutIndex
        if let selectedCutIndex {
            timelineView?.scrollToCut(index: selectedCutIndex, animated: true)
        }

        refreshCutEditors()
        cutsTableView.reloadData()
    }

    private func refreshCutEditors() {
        guard let selectedCutIndex, cuts.indices.contains(selectedCutIndex) else {
            startTextField.text = nil
            endTextField.text = nil
            return
        }

        let cut = cuts[selectedCutIndex]
        startTextField.text = VideoCutFormatting.shortTime(cut.startTime)
        endTextField.text = VideoCutFormatting.shortTime(cut.endTime)
    }

    private func seek(to time: TimeInterval) {
        let target = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private var currentTime: TimeInterval {
        CMTimeGetSeconds(player.currentTime()).isFinite ? CMTimeGetSeconds(player.currentTime()) : 0
    }

    private func refreshTimeLabel() {
        let duration = CMTimeGetSeconds(asset.duration)
        timeLabel.text = "\(VideoCutFormatting.shortTime(currentTime)) / \(VideoCutFormatting.shortTime(duration))"
    }

    private func previewSelectedSegment() {
        guard let selectedCutIndex, cuts.indices.contains(selectedCutIndex) else { return }
        let cut = cuts[selectedCutIndex]

        seek(to: cut.startTime)
        previewSegmentEndTime = cut.endTime
        player.play()
        playPauseButton.setTitle("Pause", for: .normal)
    }

    private func previewFinalVideo() {
        isPreviewingFinal = true
        seek(to: 0)
        player.play()
        playPauseButton.setTitle("Pause", for: .normal)
    }

    private func syncPreviewLimits() {
        let now = currentTime

        if let previewSegmentEndTime, now >= previewSegmentEndTime {
            player.pause()
            playPauseButton.setTitle("Play", for: .normal)
            self.previewSegmentEndTime = nil
        }

        guard isPreviewingFinal else { return }

        for cut in cuts where now >= cut.startTime && now < cut.endTime {
            seek(to: cut.endTime)
            break
        }

        let duration = CMTimeGetSeconds(asset.duration)
        if now >= duration {
            isPreviewingFinal = false
            player.pause()
            playPauseButton.setTitle("Play", for: .normal)
        }
    }

    private func parseShortTime(_ text: String) -> TimeInterval? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let minutes = Double(parts[0]),
              let seconds = Double(parts[1]) else {
            return Double(text)
        }
        return minutes * 60 + seconds
    }

    private func presentAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension VideoCutViewController: UITableViewDataSource, UITableViewDelegate {
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        cuts.count
    }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "cell")
        let cut = cuts[indexPath.row]
        let duration = max(0, cut.endTime - cut.startTime)

        cell.textLabel?.text = "\(indexPath.row + 1). \(VideoCutFormatting.shortTime(cut.startTime)) - \(VideoCutFormatting.shortTime(cut.endTime))"
        cell.detailTextLabel?.text = String(format: "%.1fs", duration)
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = .white
        cell.detailTextLabel?.textColor = .lightGray
        cell.accessoryType = indexPath.row == selectedCutIndex ? .checkmark : .none
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        selectedCutIndex = indexPath.row
        timelineView?.selectedCutIndex = selectedCutIndex
        timelineView?.scrollToCut(index: indexPath.row, animated: true)
        refreshCutEditors()
        tableView.reloadData()
    }
}
#endif
