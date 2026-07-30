import os
import pickle
import numpy as np
import mediapipe as mp
import cv2
from utils import preprocess_landmarks

# Confidence threshold for classification (0.0 to 1.0)
CONFIDENCE_THRESHOLD = 0.55

class GesturePredictor:
    def __init__(self, model_path="models/gesture_model.pkl"):
        self.model_path = model_path
        self.model = None
        self.labels = []
        self.load_model()

        # Initialize MediaPipe Hands
        self.mp_hands = mp.solutions.hands
        self.hands = self.mp_hands.Hands(
            static_image_mode=True,
            max_num_hands=1,
            min_detection_confidence=0.6,
            min_tracking_confidence=0.6
        )

    def load_model(self):
        if os.path.exists(self.model_path):
            try:
                with open(self.model_path, "rb") as f:
                    data = pickle.load(f)
                    self.model = data["model"]
                    self.labels = data["labels"]
                print(f"Model loaded successfully from '{self.model_path}'. Labels: {self.labels}")
            except Exception as e:
                print(f"Error loading model from {self.model_path}: {e}")
        else:
            print(f"Warning: Model file '{self.model_path}' not found. Inference will return None.")

    def predict(self, frame):
        """
        Predict gesture from a camera frame.

        Args:
            frame: OpenCV image (BGR)

        Returns:
            dict: {
                "gesture": str or None,
                "confidence": float,
                "hand_detected": bool
            }
        """
        # IMPORTANT: collect_data.py flips frames horizontally (selfie view)
        # before extracting landmarks. We must do the same here, or live
        # landmarks will be mirror-opposite of what the model was trained on.
        frame = cv2.flip(frame, 1)

        # Convert BGR to RGB
        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)

        # Process image with MediaPipe
        results = self.hands.process(rgb_frame)

        # 1. Check if hands are detected
        if not results.multi_hand_landmarks:
            return {
                "gesture": None,
                "confidence": 0.0,
                "hand_detected": False
            }

        # If model is not loaded yet, return None but indicate hand was detected
        if self.model is None:
            return {
                "gesture": None,
                "confidence": 0.0,
                "hand_detected": True
            }

        # Process the first detected hand
        hand_landmarks = results.multi_hand_landmarks[0]

        try:
            # 2. Extract and preprocess landmarks
            features = preprocess_landmarks(hand_landmarks)

            # 3. Predict class probabilities
            probabilities = self.model.predict_proba([features])[0]
            max_idx = np.argmax(probabilities)
            confidence = float(probabilities[max_idx])
            predicted_label = self.labels[max_idx]

            print(f"[predict] label={predicted_label!r} confidence={confidence:.3f} threshold={CONFIDENCE_THRESHOLD}")

            # 4. Filter predictions based on confidence and "No Gesture" (background class)
            if confidence < CONFIDENCE_THRESHOLD:
                return {
                    "gesture": None,
                    "confidence": confidence,
                    "hand_detected": True
                }

            if predicted_label.lower() == "no gesture" or predicted_label.lower() == "background":
                return {
                    "gesture": None,
                    "confidence": confidence,
                    "hand_detected": True
                }

            return {
                "gesture": predicted_label,
                "confidence": confidence,
                "hand_detected": True
            }

        except Exception as e:
            print(f"Error during gesture inference: {e}")
            return {
                "gesture": None,
                "confidence": 0.0,
                "hand_detected": True
            }

    def close(self):
        self.hands.close()