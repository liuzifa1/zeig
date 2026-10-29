# SearchFeature

The Search tab (`Tab(role: .search)`): file names anywhere in the library, with an
All Files | Archives switch (`ScopeSwitcher` in `.pinnedTopBar`) showing counts, and the title
as a `LargeTitleItem`.

`SearchSession` holds the field's state and explains where `.searchable` must go on iOS 26+
(on this tab's NavigationStack, never on the TabView). Learned in HNReader.
