import SwiftUI
import ZeigCore
import ZeigDesign

/// Settings → Format Guide: every topic, formats first.
public struct FormatGuideView: View {
    @Environment(\.fontTheme) private var fonts

    public init() {}

    public var body: some View {
        List {
            Section("Formats") {
                ForEach(GuideTopic.formats) { link($0) }
            }
            Section("Settings when creating") {
                ForEach(GuideTopic.settings) { link($0) }
            }
        }
        .navigationTitle("Format Guide")
        .inlineNavigationTitle()
    }

    private func link(_ topic: GuideTopic) -> some View {
        NavigationLink {
            GuideTopicView(topic: topic)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(topic.title)
                Text(topic.summary).font(fonts.font(.guide, .caption)).foregroundStyle(.secondary)
            }
        }
    }
}

/// One topic's full explanation.
public struct GuideTopicView: View {
    let topic: GuideTopic
    @Environment(\.fontTheme) private var fonts

    public init(topic: GuideTopic) {
        self.topic = topic
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(topic.summary)
                    .font(fonts.font(.guide, .headline, weight: .semibold))
                ForEach(topic.body, id: \.self) { paragraph in
                    Text(paragraph)
                        .font(fonts.font(.guide, .body))
                }
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(topic.title)
        .inlineNavigationTitle()
    }
}
