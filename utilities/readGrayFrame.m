function I = readGrayFrame(v, idx)
    I = read(v, idx);
    if size(I, 3) == 3
        I = rgb2gray(I);
    end
end