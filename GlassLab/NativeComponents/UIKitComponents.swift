import SwiftUI
import UIKit

/// Standalone UIKit bars and controls placed directly over an experiment background.
struct UIKitBarSubject: UIViewRepresentable {
    var kind: SubjectKind
    var width: Double

    static func height(for kind: SubjectKind) -> Double {
        switch kind {
        case .uikitNavigationBar: return 54
        case .uikitToolbar: return 50
        case .uikitTabBar: return 64
        default: return 36
        }
    }

    func makeUIView(context: Context) -> UIView {
        switch kind {
        case .uikitNavigationBar:
            let bar = UINavigationBar()
            let item = UINavigationItem(title: "Title")
            item.leftBarButtonItem = UIBarButtonItem(systemItem: .close)
            item.rightBarButtonItems = [UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil),
                                        UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil)]
            bar.items = [item]
            return bar
        case .uikitToolbar:
            let bar = UIToolbar()
            bar.items = [UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: nil, action: nil),
                         .flexibleSpace(),
                         UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain, target: nil, action: nil),
                         UIBarButtonItem(image: UIImage(systemName: "book"), style: .plain, target: nil, action: nil),
                         .flexibleSpace(),
                         UIBarButtonItem(image: UIImage(systemName: "square.on.square"), style: .plain, target: nil, action: nil)]
            return bar
        case .uikitTabBar:
            let bar = UITabBar()
            let items = [("Home", "house"), ("Search", "magnifyingglass"), ("Library", "books.vertical"), ("Settings", "gearshape")]
            bar.items = items.enumerated().map { UITabBarItem(title: $0.element.0, image: UIImage(systemName: $0.element.1), tag: $0.offset) }
            bar.selectedItem = bar.items?.first
            return bar
        default:
            let s = UISegmentedControl(items: ["One", "Two", "Three"])
            s.selectedSegmentIndex = 0
            return s
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// A UIKit navigation controller hosting a scrolling image list, for navigation bar, toolbar,
/// large title and scroll-edge studies.
struct UIKitNavigationDemo: UIViewControllerRepresentable {
    var largeTitles: Bool
    var showToolbar: Bool

    func makeUIViewController(context: Context) -> UINavigationController {
        let root = UIKitScrollListController()
        root.title = "UIKit Navigation"
        root.navigationItem.rightBarButtonItems = [
            UIBarButtonItem(image: UIImage(systemName: "plus"), style: .plain, target: nil, action: nil),
            UIBarButtonItem(image: UIImage(systemName: "ellipsis"), style: .plain, target: nil, action: nil),
        ]
        root.navigationItem.searchController = UISearchController()
        let nav = UINavigationController(rootViewController: root)
        nav.navigationBar.prefersLargeTitles = largeTitles
        nav.isToolbarHidden = !showToolbar
        root.toolbarItems = [UIBarButtonItem(systemItem: .action), .flexibleSpace(), UIBarButtonItem(systemItem: .bookmarks)]
        return nav
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        nav.navigationBar.prefersLargeTitles = largeTitles
        nav.setToolbarHidden(!showToolbar, animated: true)
    }
}

final class UIKitScrollListController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 60 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let c = tableView.dequeueReusableCell(withIdentifier: "c", for: indexPath)
        var cfg = c.defaultContentConfiguration()
        cfg.text = "Row \(indexPath.row + 1)"
        cfg.secondaryText = "Scroll content under the bars"
        cfg.image = UIImage(systemName: ["circle.fill", "square.fill", "triangle.fill", "diamond.fill"][indexPath.row % 4])
        cfg.imageProperties.tintColor = [UIColor.systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple][indexPath.row % 5]
        c.contentConfiguration = cfg
        c.accessoryType = .disclosureIndicator
        return c
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let detail = UIViewController()
        detail.view.backgroundColor = .systemBackground
        detail.title = "Row \(indexPath.row + 1)"
        navigationController?.pushViewController(detail, animated: true)
    }
}

/// UITabBarController with four tabs.
struct UIKitTabBarDemo: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UITabBarController {
        let tc = UITabBarController()
        let specs = [("Home", "house"), ("Search", "magnifyingglass"), ("Library", "books.vertical"), ("Settings", "gearshape")]
        tc.viewControllers = specs.map { title, icon in
            let list = UIKitScrollListController()
            list.title = title
            let nav = UINavigationController(rootViewController: list)
            nav.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: icon), selectedImage: nil)
            return nav
        }
        tc.tabBarMinimizeBehavior = .onScrollDown
        return tc
    }
    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {}
}

/// Presents UIKit sheets, alerts and popovers from a hosting controller.
struct UIKitPresenter: UIViewControllerRepresentable {
    enum Request: Equatable { case none, sheetMedium, sheetLarge, alert, actionSheet, popover }
    @Binding var request: Request

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {
        guard request != .none, vc.presentedViewController == nil, vc.view.window != nil else { return }
        let req = request
        DispatchQueue.main.async { request = .none }
        switch req {
        case .sheetMedium, .sheetLarge:
            let sheet = UIViewController()
            sheet.view.backgroundColor = .clear
            let label = UILabel()
            label.text = req == .sheetMedium ? "UISheetPresentationController · .medium()" : "UISheetPresentationController · .large()"
            label.font = .preferredFont(forTextStyle: .headline)
            label.translatesAutoresizingMaskIntoConstraints = false
            sheet.view.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: sheet.view.centerXAnchor),
                                         label.topAnchor.constraint(equalTo: sheet.view.topAnchor, constant: 32)])
            if let s = sheet.sheetPresentationController {
                s.detents = req == .sheetMedium ? [.medium(), .large()] : [.large()]
                s.prefersGrabberVisible = true
            }
            vc.present(sheet, animated: true)
        case .alert, .actionSheet:
            let a = UIAlertController(title: "UIAlertController", message: "System alert rendered by UIKit.",
                                      preferredStyle: req == .alert ? .alert : .actionSheet)
            a.addAction(UIAlertAction(title: "OK", style: .default))
            a.addAction(UIAlertAction(title: "Delete", style: .destructive))
            a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            if let pop = a.popoverPresentationController { pop.sourceView = vc.view; pop.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1) }
            vc.present(a, animated: true)
        case .popover:
            let p = UIViewController()
            p.preferredContentSize = CGSize(width: 280, height: 160)
            let label = UILabel(); label.text = "UIKit popover"; label.frame = CGRect(x: 20, y: 20, width: 240, height: 30)
            p.view.addSubview(label)
            p.modalPresentationStyle = .popover
            if let pop = p.popoverPresentationController {
                pop.sourceView = vc.view
                pop.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1)
            }
            vc.present(p, animated: true)
        case .none: break
        }
    }
}

/// A UITextView with the system edit menu (UIEditMenuInteraction is used by the text system).
struct UIKitEditMenuDemo: UIViewRepresentable {
    func makeUIView(context: Context) -> UITextView {
        let t = UITextView()
        t.text = "Select text here to open the system edit menu (UIEditMenuInteraction). Copy, Look Up, Translate and Share are provided by the system."
        t.font = .preferredFont(forTextStyle: .body)
        t.isEditable = false
        t.backgroundColor = .clear
        return t
    }
    func updateUIView(_ uiView: UITextView, context: Context) {}
}
