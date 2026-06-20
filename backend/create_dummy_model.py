import os
import pickle
import numpy as np
from sklearn.ensemble import RandomForestClassifier

def main():
    model_dir = "models"
    os.makedirs(model_dir, exist_ok=True)
    model_path = os.path.join(model_dir, "gesture_model.pkl")

    print("Generating synthetic hand landmark data...")
    # 63 features (21 landmarks * 3 coordinates)
    n_samples_per_class = 50
    
    # Class 0: "No Gesture" (random uniform noise between -1 and 1)
    class_0_features = np.random.uniform(-1.0, 1.0, (n_samples_per_class, 63))
    class_0_labels = ["No Gesture"] * n_samples_per_class
    
    # Class 1: "hello" (random noise centered around 0.5)
    class_1_features = np.random.normal(0.5, 0.1, (n_samples_per_class, 63))
    class_1_labels = ["hello"] * n_samples_per_class
    
    # Class 2: "thank_you" (random noise centered around -0.5)
    class_2_features = np.random.normal(-0.5, 0.1, (n_samples_per_class, 63))
    class_2_labels = ["thank_you"] * n_samples_per_class

    X = np.vstack([class_0_features, class_1_features, class_2_features])
    y = np.array(class_0_labels + class_1_labels + class_2_labels)

    print("Training dummy Random Forest model...")
    model = RandomForestClassifier(n_estimators=10, random_state=42)
    model.fit(X, y)

    model_data = {
        "model": model,
        "labels": list(model.classes_)
    }

    with open(model_path, "wb") as f:
        pickle.dump(model_data, f)

    print(f"Dummy model generated successfully and saved to '{model_path}'")
    print(f"Classes: {model_data['labels']}")

if __name__ == "__main__":
    main()
