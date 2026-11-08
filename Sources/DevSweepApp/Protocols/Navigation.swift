/// The screen the window shows, and showing another.
///
/// `WindowViewModel` conforms. `OverviewViewModel` shows the overview when a
/// family is picked; `AndroidViewModel` reads which Android screen shows.
@MainActor
protocol Navigation: AnyObject {
    var screen: WindowViewModel.Screen { get }
    func show(_ screen: WindowViewModel.Screen)
}
