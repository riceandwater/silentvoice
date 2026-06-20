import numpy as np

def preprocess_landmarks(hand_landmarks):
    """
    Normalizes hand landmarks to achieve translation and scale invariance.
    
    Args:
        hand_landmarks: MediaPipe normalized hand landmarks object or a list of dictionaries/points
        
    Returns:
        np.ndarray: A flattened 1D array of 63 features (21 landmarks * 3 coordinates)
    """
    # Check if we have hand_landmarks with .landmark attribute (MediaPipe object)
    if hasattr(hand_landmarks, 'landmark'):
        coords = np.array([[lm.x, lm.y, lm.z] for lm in hand_landmarks.landmark])
    else:
        # Fallback if it is passed as a raw array or list of objects/dicts
        coords = np.array([[lm['x'], lm['y'], lm['z']] for lm in hand_landmarks])
        
    # 1. Translate relative to wrist (landmark 0)
    wrist = coords[0]
    coords_relative = coords - wrist
    
    # 2. Flatten coordinates to 1D (shape: 63,)
    flat_coords = coords_relative.flatten()
    
    # 3. Scale normalize to scale invariance
    max_val = np.max(np.abs(flat_coords))
    if max_val > 0:
        flat_coords = flat_coords / max_val
        
    return flat_coords
