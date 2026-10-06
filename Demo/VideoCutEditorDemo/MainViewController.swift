import UIKit
import PhotosUI
import AVFoundation
import AVKit
import VideoCutEditor

final class MainViewController: UIViewController {
    private let selectVideoButton = UIButton(type: .system)
    private let openEditorButton = UIButton(type: .system)
    private let clearFilesButton = UIButton(type: .system)
    private let statusLabel = UILabel()

    private var selectedVideoURL: URL?
    private var demoCuts: [VideoCut] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "VideoCutEditor Demo"
        setupUI()
    }

    private func setupUI() {
        selectVideoButton.setTitle("Select Video", for: .normal)
        openEditorButton.setTitle("Open Video Cut Editor", for: .normal)
        clearFilesButton.setTitle("Clear Temporary Files", for: .normal)

        [selectVideoButton, openEditorButton, clearFilesButton].forEach {
            $0.configuration = .filled()
            $0.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        }

        openEditorButton.isEnabled = false

        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.text = "No video selected"

        let stack = UIStackView(arrangedSubviews: [selectVideoButton, openEditorButton, clearFilesButton, statusLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func buttonTapped(_ sender: UIButton) {
        switch sender {
        case selectVideoButton:
            var config = PHPickerConfiguration(photoLibrary: .shared())
            config.filter = .videos
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
        case openEditorButton:
            openEditor()
        case clearFilesButton:
            VideoCutFileManager.clearTemporaryFiles()
            statusLabel.text = "Temporary files cleared"
        default:
            break
        }
    }

    private func openEditor() {
        guard let selectedVideoURL else { return }
        let editor = VideoCutViewController(videoURL: selectedVideoURL, cuts: demoCuts)
        editor.onExportCompleted = { [weak self] outputURL in
            self?.playResult(url: outputURL)
        }

        let navigationController = UINavigationController(rootViewController: editor)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }

    private func playResult(url: URL) {
        statusLabel.text = "Exported: \(url.lastPathComponent)"
        let playerVC = AVPlayerViewController()
        playerVC.player = AVPlayer(url: url)
        present(playerVC, animated: true) {
            playerVC.player?.play()
        }
    }

    private func generateDemoCuts(duration: TimeInterval) -> [VideoCut] {
        let candidates: [VideoCut] = [
            VideoCut(startTime: 5, endTime: 10),
            VideoCut(startTime: 20, endTime: 30)
        ]

        return VideoCutValidator.normalizedCuts(candidates, duration: duration)
    }
}

extension MainViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard let itemProvider = results.first?.itemProvider,
              itemProvider.hasItemConformingToTypeIdentifier("public.movie") else {
            return
        }

        itemProvider.loadFileRepresentation(forTypeIdentifier: "public.movie") { [weak self] url, _ in
            guard let self, let url else { return }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("demo-selected-video-\(UUID().uuidString).mov")
            try? FileManager.default.removeItem(at: tempURL)
            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                let asset = AVURLAsset(url: tempURL)
                let duration = CMTimeGetSeconds(asset.duration)
                let cuts = self.generateDemoCuts(duration: duration)

                DispatchQueue.main.async {
                    self.selectedVideoURL = tempURL
                    self.demoCuts = cuts
                    self.openEditorButton.isEnabled = true
                    self.statusLabel.text = "Selected: \(tempURL.lastPathComponent)\nCuts: \(cuts.count)"
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusLabel.text = "Failed to copy selected video"
                }
            }
        }
    }
}
