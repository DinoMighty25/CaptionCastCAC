
import SwiftUI

struct AssignParticipantSheet: View {
    @Environment(\.dismiss) private var dismiss
    let participants: [User]
    let onSelectParticipant: (User) -> Void
    
    var body: some View {
        NavigationView {
            List(participants) { user in
                Button(action: {
                    onSelectParticipant(user)
                    dismiss()
                }) {
                    HStack {
                        Text(user.name)
                            .foregroundColor(user.color.color)
                        Spacer()
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .navigationTitle("Assign to Face")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
