import GRumpAppCore

@main
struct GRumpExecutable {
    @MainActor
    static func main() {
        GRumpApplication.launch()
    }
}
