import SwiftUI
import AVKit


// Settings View that shows cached videos and allows management
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SettingsViewModel()
    @State private var showingDeleteConfirmation = false
    @State private var videoToDelete: CachedVideoItem?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Cache Settings")) {
                    Toggle("Enable Video Caching", isOn: $viewModel.isCachingEnabled)
                        .onChange(of: viewModel.isCachingEnabled) { newValue in
                            viewModel.toggleCaching(enabled: newValue)
                        }
                    
                    Button(action: {
                        viewModel.clearAllCache()
                    }) {
                        HStack {
                            Text("Clear All Cache")
                                .foregroundColor(.red)
                            Spacer()
                            Text("\(viewModel.totalCacheSize)")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section(header: Text("Cached Videos")) {
                    if viewModel.isLoading {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding()
                            Spacer()
                        }
                    } else if viewModel.cachedVideos.isEmpty {
                        Text("No cached videos")
                            .foregroundColor(.gray)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    } else {
                        ForEach(viewModel.cachedVideos) { video in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(video.filename)
                                        .lineLimit(1)
                                    Text("Size: \(video.size)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text("Cached: \(viewModel.formatDate(video.date))")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                
                                Button(action: {
                                    videoToDelete = video
                                    showingDeleteConfirmation = true
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        viewModel.loadCachedVideos()
                    }
                }
            }
            .refreshable {
                viewModel.loadCachedVideos()
            }
            .alert(isPresented: $showingDeleteConfirmation) {
                Alert(
                    title: Text("Delete Cache"),
                    message: Text("Are you sure you want to delete this cached video?"),
                    primaryButton: .destructive(Text("Delete")) {
                        if let video = videoToDelete {
                            viewModel.deleteCache(for: video)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear {
            viewModel.loadCachedVideos()
        }
    }
}
