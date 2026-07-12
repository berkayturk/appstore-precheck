import SwiftUI

struct RecipeListView: View {
    let recipes = ["Lentil Soup", "Shakshuka", "Baked Ziti"]

    var body: some View {
        NavigationStack {
            List(recipes, id: \.self) { recipe in
                Text(recipe)
            }
            .navigationTitle("My Recipes")
        }
    }
}
