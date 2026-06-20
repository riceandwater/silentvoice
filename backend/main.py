import io
import cv2
import numpy as np
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from inference import GesturePredictor

app = FastAPI(title="SilentVoice (Vapp) Sign Gesture AI Backend")

# Enable CORS for Flutter app communication
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Instantiate the gesture predictor (loads model dynamically at startup)
predictor = GesturePredictor()

@app.get("/health")
def health_check():
    """Simple health check endpoint."""
    return {
        "status": "healthy",
        "model_loaded": predictor.model is not None,
        "supported_labels": predictor.labels
    }

@app.post("/predict")
async def predict_frame(file: UploadFile = File(...)):
    """
    Receives an image frame, performs sign language gesture recognition,
    and returns predicted gesture and confidence.
    """
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Invalid file type. Please upload an image.")
        
    try:
        # Read file bytes
        contents = await file.read()
        
        # Convert bytes to numpy array
        nparr = np.frombuffer(contents, np.uint8)
        
        # Decode image using OpenCV
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        if frame is None:
            raise HTTPException(status_code=400, detail="Failed to decode image frame.")
            
        # Perform prediction
        result = predictor.predict(frame)
        return result
        
    except Exception as e:
        print(f"Error handling /predict request: {e}")
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")

@app.post("/reload")
def reload_model():
    """Endpoint to reload the model from disk (e.g. after training)."""
    predictor.load_model()
    return {
        "status": "success",
        "model_loaded": predictor.model is not None,
        "supported_labels": predictor.labels
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
