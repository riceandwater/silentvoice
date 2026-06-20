import os
import pickle
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, accuracy_score

def main():
    csv_path = "data/gestures.csv"
    model_dir = "models"
    os.makedirs(model_dir, exist_ok=True)
    
    if not os.path.exists(csv_path):
        print(f"Error: The dataset file '{csv_path}' does not exist.")
        print("Please run 'collect_data.py' first to collect landmark data.")
        return

    # Load dataset
    print(f"Loading dataset from '{csv_path}'...")
    data = pd.read_csv(csv_path, header=None)
    
    # Extract labels (col 0) and features (cols 1-63)
    y = data.iloc[:, 0].values
    X = data.iloc[:, 1:].values
    
    # Print class distribution
    unique_classes, counts = np.unique(y, return_counts=True)
    print("\nClass distribution:")
    for cls, count in zip(unique_classes, counts):
        print(f"  {cls}: {count} samples")
        
    if len(unique_classes) < 2:
        print("\nError: You must record data for at least two classes to train a classifier.")
        return

    # Train-test split
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    print(f"\nTraining dataset size: {X_train.shape[0]} samples")
    print(f"Testing dataset size: {X_test.shape[0]} samples")

    # Initialize and train Random Forest Classifier
    # RandomForest is chosen for fast training, inference speed, and excellent probability calibration
    model = RandomForestClassifier(n_estimators=100, random_state=42, min_samples_split=4)
    print("\nTraining Random Forest model...")
    model.fit(X_train, y_train)

    # Evaluate the model
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    print(f"\nModel Accuracy: {accuracy * 100:.2f}%")
    print("\nClassification Report:")
    print(classification_report(y_test, y_pred))

    # Save model and label mapping
    model_path = os.path.join(model_dir, "gesture_model.pkl")
    model_data = {
        "model": model,
        "labels": list(model.classes_)
    }
    
    with open(model_path, "wb") as f:
        pickle.dump(model_data, f)
        
    print(f"\nSuccessfully trained model and saved to '{model_path}'")

if __name__ == "__main__":
    main()
