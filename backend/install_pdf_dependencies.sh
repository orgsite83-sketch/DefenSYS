#!/bin/bash
# Install dependencies for PDF generation feature

echo "📦 Installing PDF generation dependencies..."
echo ""

# Check if virtual environment is activated
if [[ -z "$VIRTUAL_ENV" ]]; then
    echo "⚠️  Warning: No virtual environment detected."
    echo "   It's recommended to activate your virtual environment first."
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Install reportlab
echo "Installing reportlab..."
pip install reportlab

# Verify installation
echo ""
echo "✅ Verifying installation..."
python -c "import reportlab; print(f'ReportLab version: {reportlab.Version}')" 2>/dev/null

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ PDF generation dependencies installed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Run the test script: python test_pdf_generation.py"
    echo "2. Start the Django server: python manage.py runserver"
    echo "3. Test the feature in the frontend"
else
    echo ""
    echo "❌ Installation verification failed. Please check for errors above."
    exit 1
fi
