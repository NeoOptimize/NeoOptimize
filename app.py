import gradio as gr
import sys
import os

# Tambahkan path
sys.path.append(os.path.dirname(__file__))

# Import fungsi dari app.main
try:
    from app.main import chat_with_memory
except ImportError as e:
    print(f"Import error: {e}")
    # Fallback function jika import gagal
    def chat_with_memory(message, history, client_id=None):
        return f"Fungsi chat sementara tidak tersedia. Error: {e}"

def respond(message, chat_history):
    if not message.strip():
        return "", chat_history
    
    try:
        response = chat_with_memory(message, chat_history, client_id=None)
        chat_history.append((message, response))
    except Exception as e:
        chat_history.append((message, f"Error: {str(e)}"))
    
    return "", chat_history

# Buat interface Gradio
with gr.Blocks(title="Neo AI", theme=gr.themes.Soft()) as demo:
    gr.Markdown("# 🤖 Neo AI - Asisten Windows")
    chatbot = gr.Chatbot(height=400)
    msg = gr.Textbox(label="Pesan", placeholder="Ketik perintah...")
    clear = gr.Button("Hapus")
    
    msg.submit(respond, [msg, chatbot], [msg, chatbot])
    clear.click(lambda: None, None, chatbot)

# Untuk lokal testing
if __name__ == "__main__":
    demo.launch(server_name="0.0.0.0", server_port=7860)