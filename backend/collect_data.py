import os
import cv2
import csv
import argparse
import time
import mediapipe as mp
from utils import preprocess_landmarks

def main():
        parser = argparse.ArgumentParser(description="Collect hand gesture landmarks for training.")
        parser.add_argument("--gesture", type=str, required=True, 
                            help="Name of the gesture (e.g. 'hello', 'No Gesture', 'thank_you')")
        parser.add_argument("--samples", type=int, default=300, 
                            help="Number of samples to collect (default: 300)")
        parser.add_argument("--output", type=str, default="data/gestures.csv", 
                            help="Path to the output CSV file")
        
        args = parser.parse_args()
        
        # Add this line right here to normalize the input string:
        args.gesture = args.gesture.strip().lower().replace(" ", "_") 

        # Ensure output directory exists
        os.makedirs(os.path.dirname(args.output), exist_ok=True)

        # Initialize MediaPipe Hands
        mp_hands = mp.solutions.hands
        mp_drawing = mp.solutions.drawing_utils
        mp_drawing_styles = mp.solutions.drawing_styles
        
        hands = mp_hands.Hands(
            static_image_mode=False,
            max_num_hands=1,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )

        cap = cv2.VideoCapture(0)
        if not cap.isOpened():
            print("Error: Could not open webcam.")
            return

        count = 0
        recording = False
        print(f"Data collection for gesture: '{args.gesture}'")
        print("Instructions:")
        print("  1. Position your hand in front of the camera.")
        print("  2. Press 'r' to START/PAUSE recording.")
        print("  3. Press 'q' to QUIT.")
        
        while cap.isOpened() and count < args.samples:
            success, image = cap.read()
            if not success:
                print("Ignoring empty camera frame.")
                continue

            # Flip image horizontally for a selfie-view display
            image = cv2.flip(image, 1)
            
            # Convert the BGR image to RGB
            image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            results = hands.process(image_rgb)

            # Draw hand landmarks
            if results.multi_hand_landmarks:
                for hand_landmarks in results.multi_hand_landmarks:
                    mp_drawing.draw_landmarks(
                        image,
                        hand_landmarks,
                        mp_hands.HAND_CONNECTIONS,
                        mp_drawing_styles.get_default_hand_landmarks_style(),
                        mp_drawing_styles.get_default_hand_connections_style()
                    )
                    
                    # If recording is active, preprocess and save landmarks
                    if recording:
                        try:
                            features = preprocess_landmarks(hand_landmarks)
                            
                            # Save to CSV
                            with open(args.output, 'a', newline='') as f:
                                writer = csv.writer(f)
                                row = [args.gesture] + list(features)
                                writer.writerow(row)
                                
                            count += 1
                        except Exception as e:
                            print(f"Error preprocessing frame: {e}")

            # Display instructions on screen
            status_text = f"Recording: {recording} | Count: {count}/{args.samples}"
            color = (0, 0, 255) if not recording else (0, 255, 0)
            cv2.putText(image, status_text, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)
            cv2.putText(image, f"Gesture: {args.gesture}", (10, 60), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 0), 2)
            cv2.putText(image, "Press 'r' to toggle Rec | 'q' to Quit", (10, 450), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 255), 1)

            cv2.imshow('SilentVoice Data Collection', image)
            
            key = cv2.waitKey(5) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('r'):
                recording = not recording
                print(f"Recording status: {recording}")
                time.sleep(0.3)  # Debounce

        cap.release()
        cv2.destroyAllWindows()
        hands.close()
        print(f"Finished collecting {count} samples for gesture '{args.gesture}'. Saved to {args.output}")

if __name__ == "__main__":
 main()
